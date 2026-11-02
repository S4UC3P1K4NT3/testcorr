#!/usr/bin/env bash
# Testeur complet ft_printf (42)
# Usage : ./file.sh [chemin_du_projet]   (par defaut : dossier courant)

G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
W=45
OK=0
KO=0
TEST_STATUS=1
CC=${CC:-cc}
MAIN_RE='int[[:space:]]+main[[:space:]]*[(]'

ok()      { printf "  %-${W}s${G}ok${N}\n" "$1"; OK=$((OK + 1)); }
ko()      { printf "  %-${W}s${R}KO${N}\n" "$1"; [ -n "$2" ] && printf '%s\n' "$2" | sed 's/^/      /'; KO=$((KO + 1)); }
warn()    { printf "  %-${W}s${Y}%s${N}\n" "$1" "$2"; }
section() { printf "\n${B}[ %s ]${N}\n" "$1"; }
pfind()   { find . -not -path '*/.*' -not -ipath '*tester*' -not -ipath '*francinette*' "$@"; }
in_list() { local x=$1 e; shift; for e; do [ "$e" = "$x" ] && return 0; done; return 1; }

DIR=$(cd "${1:-.}" 2>/dev/null && pwd) || { echo "Dossier introuvable : ${1:-.}"; exit 2; }
cd "$DIR" || exit 2
LIB="$DIR/libftprintf.a"
TMP=$(mktemp -d /tmp/ft_printf_check.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/make.log"

# Supprime les commentaires // et /* */ (en respectant les chaines)
cat > "$TMP/strip.pl" <<'PL_EOF'
undef $/;
my $s = <>;
$s =~ s{/[*].*?[*]/|//[^\n]*|("(?:\x5c.|[^"\x5c\n])*"|'(?:\x5c.|[^'\x5c\n])*')}{defined $1 ? $1 : " "}gse;
print $s;
PL_EOF
has_main() {
	if command -v perl >/dev/null 2>&1; then
		perl "$TMP/strip.pl" "$1" | grep -qE "$MAIN_RE"
	else
		grep -vE '^[[:space:]]*//' "$1" | grep -qE "$MAIN_RE"
	fi
}

printf "${B}Projet teste : %s${N}\n" "$DIR"

# ============================ MAKEFILE ============================
section "Makefile"
if [ ! -f Makefile ]; then
	ko "Makefile present" "aucun Makefile dans $DIR"
	exit 1
fi
ok "Makefile present"

missing=""
for rule in all clean fclean re; do
	grep -qE "^${rule}[[:space:]]*:" Makefile || missing="$missing $rule"
done
grep -qE '^[$][({]NAME[)}][[:space:]]*:' Makefile || missing="$missing \$(NAME)"
if [ -z "$missing" ]; then ok "regles all clean fclean re \$(NAME)"
else ko "regles all clean fclean re \$(NAME)" "manquantes :$missing"; fi

missing=""
for flag in -Wall -Wextra -Werror; do
	grep -q -- "$flag" Makefile || missing="$missing $flag"
done
if [ -z "$missing" ]; then ok "flags -Wall -Wextra -Werror"
else ko "flags -Wall -Wextra -Werror" "manquants :$missing"; fi

if grep -qi 'libtool' Makefile; then ko "pas de libtool (interdit)"
else ok "pas de libtool (interdit)"; fi

if ! make re >"$LOG" 2>&1; then
	ko "make re" "$(tail -n 15 "$LOG")"
	exit 1
fi
if grep -qE 'warning:|error:' "$LOG"; then
	ko "compilation sans warning" "$(grep -E 'warning:|error:' "$LOG" | head -n 10)"
else ok "compilation sans warning"; fi

if [ -f "$LIB" ]; then ok "libftprintf.a cree a la racine"
else ko "libftprintf.a cree a la racine"; exit 1; fi

sleep 1; touch "$TMP/marker"
make >"$LOG" 2>&1
rebuilt=$(pfind -type f -name '*.[oa]' -newer "$TMP/marker")
if [ -z "$rebuilt" ]; then ok "pas de relink (make 2 fois)"
else ko "pas de relink (make 2 fois)" "recompile : $(echo $rebuilt)"; fi

mapfile -t HDRS < <(pfind -type f -name '*.h' | sed 's|^[.]/||' | sort -u)
if [ ${#HDRS[@]} -gt 0 ]; then
	sleep 1; touch "$TMP/marker"
	for h in "${HDRS[@]}"; do touch "$h"; done
	make >"$LOG" 2>&1
	if [ -n "$(pfind -type f -name '*.o' -newer "$TMP/marker")" ]; then
		ok "recompile si un .h change"
	else warn "recompile si un .h change" "non (conseille, pas exige)"; fi
fi

make clean >"$LOG" 2>&1
objs=$(pfind -type f -name '*.o')
if [ -z "$objs" ] && [ -f "$LIB" ]; then ok "make clean (.o supprimes, .a garde)"
else ko "make clean (.o supprimes, .a garde)" "restants : $(echo $objs) $([ -f "$LIB" ] || echo '.a supprime')"; fi

make fclean >"$LOG" 2>&1
if [ ! -f "$LIB" ] && [ -z "$(pfind -type f -name '*.o')" ]; then ok "make fclean (tout supprime)"
else ko "make fclean (tout supprime)"; fi

if ! make >"$LOG" 2>&1 || [ ! -f "$LIB" ]; then
	ko "make apres fclean" "$(tail -n 15 "$LOG")"
	exit 1
fi
ok "make apres fclean"

# ============================ SOURCES =============================
section "Sources"
mapfile -t ALL_SRC < <(pfind -type f -name '*.c' | sed 's|^[.]/||' | sort -u)
mapfile -t MK_SRC < <(LC_ALL=C make -nBw 2>/dev/null | awk -v root="$DIR" -v q="'" '
	/Entering directory/ { s = $0; gsub(/`/, q, s); split(s, a, q); st[++k] = a[2]; next }
	/Leaving directory/ { if (k > 0) k--; next }
	{ d = (k > 0 ? st[k] : root); for (i = 1; i <= NF; i++) if ($i ~ /[.]c$/) { f = $i; if (substr(f, 1, 1) != "/") f = d "/" f; print f } }' |
	while IFS= read -r f; do [ -f "$f" ] && realpath --relative-to="$DIR" "$f"; done | sort -u)

if [ ${#MK_SRC[@]} -eq 0 ]; then
	warn "sources du Makefile" "illisibles : tous les .c sont pris"
	MK_SRC=("${ALL_SRC[@]}")
else
	ok "${#MK_SRC[@]} fichier(s) .c compile(s) par le Makefile"
	printf "      %s\n" "${MK_SRC[@]}"
fi
mapfile -t EXTRA_SRC < <(comm -13 <(printf '%s\n' "${MK_SRC[@]}") <(printf '%s\n' "${ALL_SRC[@]}") | sed '/^$/d')
for f in "${EXTRA_SRC[@]}"; do warn "$f" "non suivi par le Makefile (ignore)"; done

MAINS=()
for f in "${ALL_SRC[@]}"; do has_main "$f" && MAINS+=("$f"); done

# ========================== BIBLIOTHEQUE ==========================
section "Bibliotheque"
mapfile -t LIBS_EXTRA < <(pfind -type f -name '*.a' -not -name 'libftprintf.a')

if nm "$LIB" 2>/dev/null | grep -qE ' T ft_printf$'; then ok "ft_printf definie dans la lib"
else ko "ft_printf definie dans la lib"; fi

if nm "$LIB" 2>/dev/null | grep -qE ' T main$'; then ko "pas de main dans la lib" "un main non commente est compile dans libftprintf.a"
else ok "pas de main dans la lib"; fi

defined=$(nm --defined-only "$LIB" "${LIBS_EXTRA[@]}" 2>/dev/null | awk 'NF>=3 {print $3}' | sort -u)
bad=$(nm -A -u "$LIB" 2>/dev/null | awk '{ n = split($1, p, ":"); print $NF, p[n-1] }' |
	grep -vE '^(write|malloc|free|__stack_chk_fail|_GLOBAL_OFFSET_TABLE_) ' |
	while read -r sym where; do printf '%s\n' "$defined" | grep -qx "$sym" || echo "$sym  (dans $where)"; done | sort -u)
if [ -z "$bad" ]; then ok "fonctions autorisees uniquement"
else ko "fonctions autorisees uniquement" "interdites :
$bad"; fi

# =========================== NORMINETTE ===========================
section "Norminette"
NORM=("${MK_SRC[@]}" "${HDRS[@]}")
if ! command -v norminette >/dev/null 2>&1; then
	warn "norminette" "non installee (ignore)"
elif [ ${#NORM[@]} -eq 0 ]; then
	ko "norminette" "aucun fichier .c/.h trouve"
else
	out=$(norminette "${NORM[@]}" 2>&1)
	if echo "$out" | grep -q 'Error'; then
		ko "norminette (${#NORM[@]} fichiers)" "$(echo "$out" | grep -v ': OK!$' | head -n 20)"
	else ok "norminette (${#NORM[@]} fichiers)"; fi
fi

# ============================== GIT ===============================
section "Git"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	junk=$(git ls-files | grep -E '[.](o|a|out|tmp)$')
	if [ -z "$junk" ]; then ok "pas de .o / .a dans le depot"
	else ko "pas de .o / .a dans le depot" "$(echo $junk)"; fi

	untracked=""
	for f in Makefile "${MK_SRC[@]}" "${HDRS[@]}"; do
		git ls-files --error-unmatch "$f" >/dev/null 2>&1 || untracked="$untracked $f"
	done
	if [ -z "$untracked" ]; then ok "fichiers du Makefile suivis par git"
	else ko "fichiers du Makefile suivis par git" "non suivis (ne seront pas rendus) :$untracked"; fi

	if [ -z "$(git status --porcelain --untracked-files=no)" ]; then ok "tout est commit"
	else warn "tout est commit" "modifications non commit"; fi

	ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null)
	if [ -z "$ahead" ]; then warn "tout est push" "pas de branche distante"
	elif [ "$ahead" -gt 0 ]; then warn "tout est push" "$ahead commit(s) non push"
	else ok "tout est push"; fi
else
	warn "depot git" "pas un depot git (ignore)"
fi

# ============================ VALGRIND ============================
section "Valgrind"
cat > "$TMP/mini.c" <<'MINI_EOF'
#include <limits.h>
int	ft_printf(const char *format, ...);
int	main(void)
{
	int	x;

	x = 0;
	ft_printf("%c %s %s %d %i %u %x %X %p %p %%\n", 'a', "abc", (char *)0,
		INT_MIN, INT_MAX, UINT_MAX, 255u, 255u, (void *)&x, (void *)0);
	ft_printf("abc%");
	return (0);
}
MINI_EOF
if ! command -v valgrind >/dev/null 2>&1; then
	warn "valgrind" "non installe (ignore)"
elif ! "$CC" -w "$TMP/mini.c" "$LIB" "${LIBS_EXTRA[@]}" -o "$TMP/mini" 2>"$LOG"; then
	ko "valgrind" "$(head -n 10 "$LOG")"
else
	valgrind -q --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=42 "$TMP/mini" >/dev/null 2>"$TMP/vg.log"
	if [ $? -eq 42 ]; then ko "aucune erreur memoire / fuite" "$(head -n 15 "$TMP/vg.log")"
	else ok "aucune erreur memoire / fuite"; fi
fi

# ========================== MAIN DE TEST ==========================
cat > "$TMP/main.c" <<'MAIN_EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <sys/wait.h>

int	ft_printf(const char *format, ...);

#define GREEN "\033[32m"
#define RED "\033[31m"
#define BOLD "\033[1m"
#define RESET "\033[0m"
#define NAME_W 45
#define BUF_SIZE 65536

static char				g_real_file[128];
static char				g_ft_file[128];
static char				g_exp[BUF_SIZE];
static char				g_got[BUF_SIZE];
static int				g_exp_len;
static int				g_exp_ret;
static int				g_saved;
static int				g_pipe[2];
static pid_t			g_pid;
static int				g_ok;
static int				g_ko;
static char *volatile	g_null = NULL;

static void	init_tmp_files(void)
{
	snprintf(g_real_file, sizeof(g_real_file), "/tmp/ft_printf_test_real_%d", (int)getpid());
	snprintf(g_ft_file, sizeof(g_ft_file), "/tmp/ft_printf_test_ft_%d", (int)getpid());
}

static int	read_file(const char *path, char *buf)
{
	int	fd;
	int	n;
	int	total;

	total = 0;
	fd = open(path, O_RDONLY);
	if (fd < 0)
		return (0);
	while (total < BUF_SIZE)
	{
		n = read(fd, buf + total, BUF_SIZE - total);
		if (n <= 0)
			break ;
		total += n;
	}
	close(fd);
	return (total);
}

static int	open_tmp(const char *path)
{
	int	fd;

	fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	if (fd < 0)
	{
		perror(path);
		exit(2);
	}
	return (fd);
}

static void	cap_begin(void)
{
	int	fd;

	fflush(stdout);
	g_saved = dup(1);
	fd = open_tmp(g_real_file);
	dup2(fd, 1);
	close(fd);
}

static void	cap_end(int ret)
{
	fflush(stdout);
	dup2(g_saved, 1);
	close(g_saved);
	g_exp_ret = ret;
	g_exp_len = read_file(g_real_file, g_exp);
}

static void	set_expected(const char *s, int len, int ret)
{
	memcpy(g_exp, s, len);
	g_exp_len = len;
	g_exp_ret = ret;
}

static int	child_begin(void)
{
	int	fd;

	fflush(stdout);
	if (pipe(g_pipe) < 0)
	{
		perror("pipe");
		exit(2);
	}
	g_pid = fork();
	if (g_pid < 0)
	{
		perror("fork");
		exit(2);
	}
	if (g_pid == 0)
	{
		close(g_pipe[0]);
		fd = open_tmp(g_ft_file);
		dup2(fd, 1);
		close(fd);
		alarm(3);
		return (1);
	}
	close(g_pipe[1]);
	return (0);
}

static void	child_end(int ret)
{
	if (write(g_pipe[1], &ret, sizeof(ret)) < 0)
		_exit(1);
	_exit(0);
}

static int	collect(int *ret, int *len)
{
	int	status;
	int	n;

	*ret = 0;
	waitpid(g_pid, &status, 0);
	n = read(g_pipe[0], ret, sizeof(*ret));
	close(g_pipe[0]);
	*len = read_file(g_ft_file, g_got);
	if (WIFSIGNALED(status) && WTERMSIG(status) == SIGALRM)
		return (2);
	if (WIFSIGNALED(status) || n != (int)sizeof(*ret))
		return (1);
	return (0);
}

static void	pass(void)
{
	printf(GREEN "ok" RESET "\n");
	g_ok++;
}

static void	fail(const char *why)
{
	printf(RED "%s" RESET "\n", why);
	g_ko++;
}

static void	section(const char *title)
{
	printf(BOLD "\n[ %s ]\n" RESET, title);
}

static void	show(const char *s, int len)
{
	int				i;
	unsigned char	c;

	printf("\"");
	i = 0;
	while (i < len && i < 60)
	{
		c = (unsigned char)s[i];
		if (c == '\n')
			printf("\\n");
		else if (c == '\t')
			printf("\\t");
		else if (c < 32 || c >= 127)
			printf("\\x%02x", c);
		else
			printf("%c", c);
		i++;
	}
	if (len > 60)
		printf("...");
	printf("\"");
}

static int	start_line(const char *name, int *ret, int *len)
{
	int	st;

	st = collect(ret, len);
	printf("  %-*s", NAME_W, name);
	if (st == 1)
		fail("CRASH");
	else if (st == 2)
		fail("TIMEOUT (boucle infinie ?)");
	return (st);
}

static void	report(const char *name)
{
	int	ret;
	int	len;

	if (start_line(name, &ret, &len))
		return ;
	if (ret == g_exp_ret && len == g_exp_len && memcmp(g_got, g_exp, len) == 0)
		pass();
	else
	{
		fail("KO");
		printf("      attendu : ");
		show(g_exp, g_exp_len);
		printf("  (ret %d)\n      obtenu  : ", g_exp_ret);
		show(g_got, len);
		printf("  (ret %d)\n", ret);
	}
}

static void	report_survive(const char *name)
{
	int	ret;
	int	len;

	if (start_line(name, &ret, &len) == 0)
		pass();
}

static void	report_ret(const char *name, int expected)
{
	int	ret;
	int	len;

	if (start_line(name, &ret, &len))
		return ;
	if (ret == expected)
		pass();
	else
	{
		fail("KO");
		printf("      attendu : ret %d\n      obtenu  : ret %d\n", expected, ret);
	}
}

#define T(name, fmt, ...) do { const char *f_ = (fmt); int r_; cap_begin(); r_ = printf(f_, ##__VA_ARGS__); cap_end(r_); if (child_begin()) child_end(ft_printf(f_, ##__VA_ARGS__)); report(name); } while (0)
#define R(name, fmt, ...) do { const char *f_ = (fmt); if (child_begin()) child_end(ft_printf(f_, ##__VA_ARGS__)); report_survive(name); } while (0)

int	main(void)
{
	int			x;
	void		*heap;
	static char	longstr[10001];
	static char	longfmt[5001];

	init_tmp_files();
	x = 42;
	heap = malloc(1);
	memset(longstr, 'x', 10000);
	memset(longfmt, 'y', 5000);

	section("%c");
	T("lettre", "%c", 'A');
	T("caractere nul", "%c", '\0');
	T("caractere nul entre du texte", "a%cb", '\0');
	T("espace", "%c", ' ');
	T("retour a la ligne", "%c", '\n');
	T("caractere 127 (DEL)", "%c", 127);
	T("caractere 255 (non ASCII)", "%c", 255);
	T("valeur negative (-1)", "%c", -1);
	T("trois caracteres colles", "%c%c%c", 'a', 'b', 'c');

	section("%s");
	T("chaine simple", "%s", "hello");
	T("chaine vide", "%s", "");
	T("pointeur NULL", "%s", g_null);
	T("NULL entre du texte", "a%sb", g_null);
	T("caracteres speciaux", "%s", "\t\v\f\r\n");
	T("UTF-8 / non ASCII", "%s", "h\xc3\xa9llo \xe2\x82\xac");
	T("chaine contenant des %", "%s", "%d %s %%");
	T("chaine de 10000 caracteres", "%s", longstr);
	T("deux chaines collees", "%s%s", "abc", "def");
	T("chaine vide puis NULL", "%s%s", "", g_null);

	section("%d / %i");
	T("zero", "%d", 0);
	T("un", "%d", 1);
	T("moins un", "%d", -1);
	T("9 et 10", "%d %d", 9, 10);
	T("-9 et -10", "%d %d", -9, -10);
	T("puissances de 10", "%d %d %d", 100, 1000, 1000000000);
	T("INT_MAX", "%d", INT_MAX);
	T("INT_MIN", "%d", INT_MIN);
	T("INT_MIN + 1", "%d", INT_MIN + 1);
	T("%i positif", "%i", 42);
	T("%i zero", "%i", 0);
	T("%i INT_MIN", "%i", INT_MIN);
	T("%d et %i colles", "%d%i", -42, 42);
	T("limites ensemble", "%d %i %d", INT_MIN, 0, INT_MAX);

	section("%u");
	T("zero", "%u", 0u);
	T("un", "%u", 1u);
	T("INT_MAX", "%u", (unsigned int)INT_MAX);
	T("INT_MAX + 1", "%u", (unsigned int)INT_MAX + 1u);
	T("UINT_MAX", "%u", UINT_MAX);
	T("-1 (devient UINT_MAX)", "%u", -1);
	T("INT_MIN", "%u", INT_MIN);
	T("4000000000", "%u", 4000000000u);
	T("deux %u colles", "%u%u", 1u, UINT_MAX);

	section("%x / %X");
	T("zero", "%x", 0u);
	T("1 et 9", "%x %x", 1u, 9u);
	T("10 (a / A)", "%x %X", 10u, 10u);
	T("15 et 16", "%x %x", 15u, 16u);
	T("255 et 256", "%x %x", 255u, 256u);
	T("0xdeadbeef minuscules", "%x", 0xdeadbeefu);
	T("0xDEADBEEF majuscules", "%X", 0xdeadbeefu);
	T("UINT_MAX", "%x %X", UINT_MAX, UINT_MAX);
	T("-1", "%x", -1);
	T("INT_MIN", "%X", INT_MIN);
	T("INT_MAX", "%x", INT_MAX);
	T("%x et %X colles", "%x%X", 0xabcu, 0xabcu);

	section("%p");
	T("NULL", "%p", (void *)NULL);
	T("adresse sur la pile", "%p", (void *)&x);
	T("adresse sur le tas (malloc)", "%p", heap);
	T("adresse d'une chaine litterale", "%p", (void *)"abc");
	T("adresse 1", "%p", (void *)1);
	T("adresses 15 et 16", "%p %p", (void *)15, (void *)16);
	T("LONG_MAX", "%p", (void *)LONG_MAX);
	T("LONG_MIN", "%p", (void *)LONG_MIN);
	T("ULONG_MAX", "%p", (void *)ULONG_MAX);
	T("NULL puis adresse", "%p %p", (void *)NULL, (void *)&x);

	section("%%");
	T("pourcent seul", "%%");
	T("deux pourcents", "%%%%");
	T("%%d affiche %d", "%%d");
	T("100%%", "100%%");
	T("%% puis %d", "%%%d", 42);
	T("%d puis %%", "%d%%", 42);
	T("%%c%%s%%p", "%%c%%s%%p");

	section("texte et format");
	T("format vide", "");
	T("texte sans conversion", "Hello 42!");
	T("retour a la ligne seul", "\n");
	T("\\0 au milieu du format", "ab\0cd");
	T("format de 5000 caracteres", longfmt);
	T("tabulations et retours", "\t%d\n\t%s\n", 1, "a");

	section("melanges");
	T("toutes les conversions", "%c|%s|%d|%i|%u|%x|%X|%p|%%", 'z', "ok", -42, 42, 42u, 255u, 255u, (void *)&x);
	T("toutes les limites", "%d %d %u %x %X %p %p %s", INT_MIN, INT_MAX, UINT_MAX, UINT_MAX, 0u, (void *)NULL, (void *)ULONG_MAX, g_null);
	T("20 arguments", "%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20);
	T("conversions sans separateur", "%s%d%s%x", "a", 1, "b", 255u);
	T("texte autour de tout", "[%c] [%s] [%d] [%p]", 'a', "b", 3, (void *)NULL);

	section("comportements internes");
	set_expected("abcde", 5, 2);
	if (child_begin())
	{
		ft_printf("abc");
		child_end(ft_printf("de"));
	}
	report("deux appels successifs (static)");
	set_expected("abc", 3, 1);
	if (child_begin())
	{
		ft_printf("a");
		if (write(1, "b", 1) < 0)
			_exit(1);
		child_end(ft_printf("c"));
	}
	report("pas de buffer interne");
	if (child_begin())
	{
		close(1);
		child_end(ft_printf("abc %d %s", 42, "xyz"));
	}
	report_ret("sortie fermee -> retourne -1", -1);

	section("robustesse (hors sujet, ne doit pas planter)");
	R("% en fin de chaine", "abc%");
	R("% seul", "%");
	R("conversion inconnue %y", "%y");
	R("drapeau non gere %5d", "%5d", 42);
	R("espace apres % (% d)", "% d", 42);
	R("format NULL", NULL);

	free(heap);
	unlink(g_real_file);
	unlink(g_ft_file);
	printf(BOLD "\nTests ft_printf : " RESET);
	if (g_ko == 0)
		printf(GREEN "%d/%d ok" RESET "\n", g_ok, g_ok);
	else
		printf("%d ok, " RED "%d KO" RESET " sur %d\n", g_ok, g_ko, g_ok + g_ko);
	return (g_ko != 0);
}
MAIN_EOF

printf "\n${B}=================== Tests ft_printf ===================${N}\n"
if ! "$CC" -w "$TMP/main.c" "$LIB" "${LIBS_EXTRA[@]}" -o "$TMP/test" 2>"$LOG"; then
	ko "edition de liens du main de test" "$(head -n 15 "$LOG")"
else
	"$TMP/test"
	TEST_STATUS=$?
fi

# ============================== BILAN =============================
section "Bilan"
printf "  Verifications projet : %d ok" "$OK"
if [ "$KO" -gt 0 ]; then printf ", ${R}%d KO${N}" "$KO"; fi
printf "\n"

if [ ${#MAINS[@]} -gt 0 ]; then
	printf "\n  ${Y}${B}/!\\ main non commente :${N}\n"
	for f in "${MAINS[@]}"; do
		if in_list "$f" "${MK_SRC[@]}"; then info="compile par le Makefile"
		else info="non suivi par le Makefile"; fi
		if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then info="$info, suivi par git : sera rendu"; fi
		printf "    ${Y}%s${N} (%s)\n" "$f" "$info"
	done
fi

if [ "$KO" -eq 0 ] && [ "$TEST_STATUS" -eq 0 ]; then
	printf "\n  ${G}${B}TOUT EST OK, pret a rendre${N}\n\n"
	exit 0
fi
printf "\n  ${R}${B}Il reste des KO (voir ci-dessus)${N}\n\n"
exit 1
