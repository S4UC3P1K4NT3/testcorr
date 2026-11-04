#!/bin/bash
# ============================================================
#  gnl_test.sh - testeur get_next_line (mandatory + bonus)
#  Usage : ./gnl_test.sh [dossier_du_projet]
#  Sans argument : teste le dossier courant.
# ============================================================

DIR="${1:-.}"
cd "$DIR" 2>/dev/null || { echo "Dossier introuvable : $DIR"; exit 1; }
DIR="$(pwd)"

R='\033[31m'; G='\033[32m'; Y='\033[33m'; B='\033[34m'; BD='\033[1m'; N='\033[0m'
PASS=0; FAIL=0; WARN=0; HAS_MAIN=0
ok()    { printf "  ${G}[OK]${N}   %s\n" "$1"; PASS=$((PASS + 1)); }
ko()    { printf "  ${R}[KO]${N}   %s\n" "$1"; FAIL=$((FAIL + 1)); }
warn()  { printf "  ${Y}[WARN]${N} %s\n" "$1"; WARN=$((WARN + 1)); }
info()  { printf "  ${B}[INFO]${N} %s\n" "$1"; }
title() { printf "\n${BD}${B}===== %s =====${N}\n" "$1"; }

TMP="$(mktemp -d /tmp/gnl_test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
CC=cc
CFLAGS="-Wall -Wextra -Werror"
TO=30

MAND_SRC="get_next_line.c get_next_line_utils.c"
MAND_H="get_next_line.h"
BONUS_SRC="get_next_line_bonus.c get_next_line_utils_bonus.c"
BONUS_H="get_next_line_bonus.h"

# ------------------------------------------------------------
#  main de test (ecrit dans /tmp, jamais dans ton projet)
# ------------------------------------------------------------
cat > "$TMP/main.c" <<'MAIN_EOF'
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

char	*get_next_line(int fd);

static int	check_line(char *line, int *no_nl)
{
	char	*nl;

	if (*no_nl)
		return (fprintf(stderr, "une ligne sans \\n a ete suivie d'une autre ligne\n"), 0);
	if (line[0] == '\0')
		return (fprintf(stderr, "chaine vide renvoyee au lieu de NULL\n"), 0);
	nl = strchr(line, '\n');
	if (nl && nl[1] != '\0')
		return (fprintf(stderr, "plusieurs lignes renvoyees en un seul appel\n"), 0);
	if (!nl)
		*no_nl = 1;
	return (1);
}

static int	read_all(int fd, FILE *out)
{
	char	*line;
	int		count;
	int		no_nl;

	count = 0;
	no_nl = 0;
	while ((line = get_next_line(fd)) != NULL)
	{
		if (!check_line(line, &no_nl))
			return (free(line), -1);
		fwrite(line, 1, strlen(line), out);
		free(line);
		count++;
	}
	line = get_next_line(fd);
	if (line)
	{
		free(line);
		fprintf(stderr, "un nouvel appel apres la fin ne renvoie pas NULL\n");
		return (-1);
	}
	return (count);
}

static int	is_null(int fd)
{
	char	*line;

	line = get_next_line(fd);
	if (!line)
		return (1);
	free(line);
	return (0);
}

static int	test_badfd(char *file)
{
	int	bad;
	int	fd;

	bad = 0;
	if (!is_null(-1) && ++bad)
		fprintf(stderr, "fd -1 ne renvoie pas NULL\n");
	if (!is_null(4242) && ++bad)
		fprintf(stderr, "fd 4242 (non ouvert) ne renvoie pas NULL\n");
	fd = open(file, O_RDONLY);
	close(fd);
	if (!is_null(fd) && ++bad)
		fprintf(stderr, "fd ferme ne renvoie pas NULL\n");
	fd = open(".", O_RDONLY);
	if (!is_null(fd) && ++bad)
		fprintf(stderr, "un dossier (read echoue) ne renvoie pas NULL\n");
	close(fd);
	fd = open(file, O_RDONLY);
	if (read_all(fd, stdout) <= 0 && ++bad)
		fprintf(stderr, "apres des erreurs, la lecture d'un fichier valide echoue\n");
	close(fd);
	if (bad)
		return (3);
	return (0);
}

static int	test_multi(char **av)
{
	int		fd[3];
	FILE	*out[3];
	int		done[3] = {0, 0, 0};
	int		alive;
	int		i;
	char	*line;

	for (i = 0; i < 3; i++)
	{
		fd[i] = open(av[i], O_RDONLY);
		out[i] = fopen(av[i + 3], "w");
		if (fd[i] < 0 || !out[i])
			return (perror("multi"), 1);
	}
	alive = 3;
	while (alive > 0)
	{
		for (i = 0; i < 3; i++)
		{
			if (done[i])
				continue ;
			line = get_next_line(fd[i]);
			if (!line)
			{
				done[i] = 1;
				alive--;
				continue ;
			}
			fwrite(line, 1, strlen(line), out[i]);
			free(line);
		}
	}
	for (i = 0; i < 3; i++)
	{
		close(fd[i]);
		fclose(out[i]);
	}
	return (0);
}

int	main(int ac, char **av)
{
	int	fd;
	int	n;

	if (ac == 3 && strcmp(av[1], "badfd") == 0)
		return (test_badfd(av[2]));
	if (ac == 8 && strcmp(av[1], "multi") == 0)
		return (test_multi(av + 2));
	if (ac != 2)
		return (fprintf(stderr, "usage\n"), 1);
	fd = 0;
	if (strcmp(av[1], "-") != 0)
		fd = open(av[1], O_RDONLY);
	if (fd < 0)
		return (perror(av[1]), 1);
	n = read_all(fd, stdout);
	if (fd != 0)
		close(fd);
	fflush(stdout);
	if (n < 0)
		return (3);
	fprintf(stderr, "COUNT=%d\n", n);
	return (0);
}
MAIN_EOF

# ------------------------------------------------------------
#  Fichiers de test
# ------------------------------------------------------------
F="$TMP/files"; mkdir -p "$F"
rep() { head -c "$1" /dev/zero | tr '\0' "$2"; }
: > "$F/01_fichier_vide"
printf '\n' > "$F/02_un_seul_nl"
printf '\n\n\n\n\n' > "$F/03_que_des_nl"
printf 'a' > "$F/04_un_char_sans_nl"
printf 'a\n' > "$F/05_un_char_avec_nl"
printf 'hello' > "$F/06_mot_sans_nl"
printf 'hello\n' > "$F/07_mot_avec_nl"
printf 'ligne 1\nligne 2\n' > "$F/08_deux_lignes"
printf 'ligne 1\nligne 2' > "$F/09_deux_lignes_fin_sans_nl"
{ rep 41 a; printf '\n'; } > "$F/10_ligne_41_plus_nl"
{ rep 42 b; printf '\n'; } > "$F/11_ligne_42_plus_nl"
{ rep 43 c; printf '\n'; } > "$F/12_ligne_43_plus_nl"
rep 41 d > "$F/13_41_chars_sans_nl"
rep 42 e > "$F/14_42_chars_sans_nl"
rep 43 f > "$F/15_43_chars_sans_nl"
{ rep 10000 g; printf '\n'; } > "$F/16_ligne_10000"
rep 100000 h > "$F/17_ligne_100000_sans_nl"
seq -f 'l%g' 1 1000 > "$F/18_1000_lignes_courtes"
printf '\n\na\n\nb\n\n' > "$F/19_lignes_vides_alternees"
printf '  espaces  \n\ttab\t\n \t \n' > "$F/20_espaces_et_tabs"
printf 'éàù ç €\nligne 2 ✔\n' > "$F/21_utf8"
printf 'win1\r\nwin2\r\n' > "$F/22_fins_crlf"
printf 'fin\n\n\n' > "$F/23_plusieurs_nl_a_la_fin"
seq 1 10000 > "$F/24_10000_lignes"
for i in $(seq 1 200); do rep "$i" x; echo; done > "$F/25_longueurs_1_a_200"
rep 50 ' ' > "$F/26_espaces_sans_nl"
for i in 1 2 3 4 5; do rep 41 z; echo; done > "$F/27_lignes_de_42_pile"
NB=$(ls "$F" | wc -l)

# ------------------------------------------------------------
#  Fonctions utilitaires
# ------------------------------------------------------------
strip_comments() { perl -0777 -pe 's{/[*].*?[*]/}{}gs; s{//[^\n]*}{}g' "$1"; }

check_header() {
	local h=$1
	if grep -Eq 'char[[:space:]]*[*][[:space:]]*get_next_line[[:space:]]*[(][[:space:]]*int[[:space:]]+[a-z_]*[[:space:]]*[)]' "$h"; then
		ok "$h : prototype char *get_next_line(int fd)"
	else ko "$h : prototype char *get_next_line(int fd) introuvable"; fi
	if grep -Eq '#[[:space:]]*ifndef[[:space:]]+BUFFER_SIZE' "$h"; then
		ok "$h : BUFFER_SIZE par défaut (#ifndef BUFFER_SIZE)"
	else ko "$h : pas de #ifndef BUFFER_SIZE -> ne compilera pas sans -D"; fi
	if grep -Eq '#[[:space:]]*ifndef[[:space:]]+[A-Z_]+_H' "$h"; then ok "$h : include guard"
	else warn "$h : include guard non trouvé"; fi
}

check_sources() {
	local f
	for f in "$@"; do
		if strip_comments "$f" | grep -Eq '(^|[^a-z_])main[[:space:]]*[(]'; then
			ko "$f : contient un main non commenté"; HAS_MAIN=1
		fi
		strip_comments "$f" | grep -q 'libft' && ko "$f : utilise la libft (interdite)"
		strip_comments "$f" | grep -Eq '(^|[^a-z_])lseek[[:space:]]*[(]' && ko "$f : lseek est interdit"
	done
}

check_objects() {   # $1 = libellé, $2 = 1 si bonus, reste = fichiers .c
	local label=$1 bonus=$2 od f bad glob stat nstat
	shift 2
	od="$TMP/obj_$label"; mkdir -p "$od"
	for f in "$@"; do
		if ! $CC $CFLAGS -D BUFFER_SIZE=42 -c "$f" -o "$od/${f%.c}.o" 2> "$TMP/cc.log"; then
			ko "$f ne compile pas seul avec $CFLAGS :"
			sed 's/^/        /' "$TMP/cc.log" | head -n 15
			return
		fi
	done
	ok "$label : chaque .c compile avec $CFLAGS"
	nm --defined-only "$od"/*.o 2>/dev/null | awk 'NF==3 {print $3}' | sort -u > "$TMP/def"
	nm -u "$od"/*.o 2>/dev/null | awk '$1=="U" {print $2}' | grep -v '^_' | sort -u > "$TMP/und"
	bad=$(comm -23 "$TMP/und" "$TMP/def" | grep -Ev '^(read|malloc|free)$' | tr '\n' ' ')
	if [ -z "$bad" ]; then ok "$label : seulement read, malloc, free"
	else ko "$label : fonctions interdites : $bad"; fi
	glob=$(nm "$od"/*.o 2>/dev/null | awk 'NF==3 && $2 ~ /^[BCDGRS]$/ {print $3}' | sort -u | tr '\n' ' ')
	if [ -z "$glob" ]; then ok "$label : aucune variable globale"
	else ko "$label : variable(s) globale(s) interdite(s) : $glob"; fi
	stat=$(nm "$od"/*.o 2>/dev/null | awk 'NF==3 && $2 ~ /^[bdgs]$/ {print $3}' | sort -u)
	nstat=$(printf '%s' "$stat" | grep -c .)
	if [ "$bonus" = 1 ]; then
		if [ "$nstat" -eq 1 ]; then ok "$label : une seule variable static ($stat)"
		else ko "$label : $nstat variables static (une seule autorisée) : $(echo $stat)"; fi
	else info "$label : $nstat variable(s) static : $(echo $stat)"; fi
}

build() {   # $1 = binaire, $2 = BUFFER_SIZE ("" = sans -D), $3 = 1 pour bonus
	local srcs="$MAND_SRC" def=""
	[ "$3" = 1 ] && srcs="$BONUS_SRC"
	[ -n "$2" ] && def="-D BUFFER_SIZE=$2"
	$CC $CFLAGS $def "$TMP/main.c" $srcs -o "$1" 2> "$TMP/cc.log"
}

expected_count() {
	local n
	n=$(wc -l < "$1" | tr -d ' ')
	if [ -s "$1" ] && [ "$(tail -c 1 "$1" | od -An -tx1 | tr -d ' \n')" != "0a" ]; then
		n=$((n + 1))
	fi
	echo "$n"
}

rc_msg() {
	case $1 in
		124) echo "timeout (boucle infinie ?)";;
		139) echo "segfault";;
		134) echo "abort (double free / corruption ?)";;
		3)   head -n 1 "$TMP/err";;
		*)   echo "code retour $1";;
	esac
}

run_file() {   # $1 = binaire, $2 = fichier, $3 = "stdin" (optionnel)
	local bin=$1 f=$2 rc got exp
	if [ "$3" = stdin ]; then timeout $TO "$bin" - < "$f" > "$TMP/out" 2> "$TMP/err"
	else timeout $TO "$bin" "$f" > "$TMP/out" 2> "$TMP/err"; fi
	rc=$?
	if [ $rc -ne 0 ]; then MSG=$(rc_msg $rc); return 1; fi
	if ! cmp -s "$TMP/out" "$f"; then
		MSG="sortie différente ($(cmp "$TMP/out" "$f" 2>&1 | head -n 1 | sed "s|$TMP/||g"))"
		return 1
	fi
	got=$(sed -n 's/^COUNT=//p' "$TMP/err"); exp=$(expected_count "$f")
	if [ "$got" != "$exp" ]; then MSG="$got lignes renvoyées au lieu de $exp"; return 1; fi
	return 0
}

multi_test() {   # $1 = binaire
	local o="$TMP/multi" rc
	rm -rf "$o"; mkdir -p "$o"
	timeout $TO "$1" multi "$F/18_1000_lignes_courtes" "$F/09_deux_lignes_fin_sans_nl" \
		"$F/25_longueurs_1_a_200" "$o/1" "$o/2" "$o/3" > /dev/null 2> "$TMP/err"
	rc=$?
	if [ $rc -ne 0 ]; then MSG=$(rc_msg $rc); return 1; fi
	if cmp -s "$o/1" "$F/18_1000_lignes_courtes" && cmp -s "$o/2" "$F/09_deux_lignes_fin_sans_nl" \
		&& cmp -s "$o/3" "$F/25_longueurs_1_a_200"; then return 0; fi
	MSG="lignes perdues ou mélangées entre les fd"
	return 1
}

vg() {   # $1 = libellé, reste = commande
	local label=$1 rc
	shift
	timeout 300 valgrind --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all \
		--error-exitcode=42 --log-file="$TMP/vg.log" "$@" > /dev/null 2>&1
	rc=$?
	case $rc in
		0)   ok "$label : aucune fuite ni erreur mémoire";;
		42)  ko "$label : $(grep -E 'Invalid|uninitialised|Mismatched|(lost|reachable): [1-9]' "$TMP/vg.log" \
				| head -n 2 | sed 's/^==[0-9]*== *//' | tr '\n' ' ')";;
		124) ko "$label : timeout sous valgrind";;
		*)   ko "$label : le programme a échoué (code $rc)";;
	esac
}

# ============================================================
title "1. Fichiers"
MAND_OK=1
for f in $MAND_SRC $MAND_H; do
	if [ -f "$f" ]; then ok "$f présent"; else ko "$f manquant"; MAND_OK=0; fi
done
HAS_BONUS=1
for f in $BONUS_SRC $BONUS_H; do [ -f "$f" ] || HAS_BONUS=0; done
if [ $HAS_BONUS -eq 1 ]; then info "fichiers bonus détectés : le bonus sera testé"
else info "bonus absent ou incomplet : tests bonus ignorés"; fi
[ -f Makefile ] && warn "Makefile présent : pas demandé par le sujet GNL"
if [ $MAND_OK -eq 0 ]; then printf "\n${R}Fichiers obligatoires manquants, arrêt.${N}\n"; exit 1; fi

# ============================================================
title "2. Header et contraintes"
check_header "$MAND_H"
check_sources $MAND_SRC
check_objects mandatory 0 $MAND_SRC

# ============================================================
title "3. Norminette"
if command -v norminette > /dev/null 2>&1; then
	NFILES="$MAND_SRC $MAND_H"
	[ $HAS_BONUS -eq 1 ] && NFILES="$NFILES $BONUS_SRC $BONUS_H"
	for f in $NFILES; do
		out=$(norminette "$f" 2>&1)
		if echo "$out" | grep -q "Error"; then
			ko "$f : erreurs de norme"
			echo "$out" | grep -v "Error!" | head -n 10 | sed 's/^/        /'
		else ok "$f : norme OK"; fi
	done
else warn "norminette non installée"; fi

# ============================================================
title "4. Compilation"
if build "$TMP/gnl42" 42 0; then ok "compile avec -D BUFFER_SIZE=42"
else
	ko "ne compile pas avec -D BUFFER_SIZE=42 :"
	sed 's/^/        /' "$TMP/cc.log" | head -n 20
	[ $HAS_MAIN -eq 1 ] && info "un main dans tes sources entre en conflit avec celui du testeur"
	printf "\n${R}Impossible de continuer.${N}\n"; exit 1
fi
if build "$TMP/gnl_nod" "" 0; then
	ok "compile sans -D BUFFER_SIZE"
	if run_file "$TMP/gnl_nod" "$F/24_10000_lignes"; then ok "fonctionne avec le BUFFER_SIZE par défaut"
	else ko "BUFFER_SIZE par défaut : $MSG"; fi
else ko "ne compile pas sans -D BUFFER_SIZE"; fi

# ============================================================
title "5. Tests BUFFER_SIZE=42"
for f in "$F"/*; do
	name=$(basename "$f"); name="${name//_/ }"
	if run_file "$TMP/gnl42" "$f"; then ok "$name"; else ko "$name : $MSG"; fi
done
if run_file "$TMP/gnl42" "$F/24_10000_lignes" stdin; then ok "28 lecture sur stdin (fd 0)"
else ko "28 lecture sur stdin : $MSG"; fi
timeout $TO "$TMP/gnl42" badfd "$F/08_deux_lignes" > /dev/null 2> "$TMP/err"; rc=$?
if [ $rc -eq 0 ]; then ok "29 fd invalides (-1, 4242, fd fermé, dossier) -> NULL"
else ko "29 fd invalides : $(rc_msg $rc)"; fi

# ============================================================
title "6. Autres BUFFER_SIZE"
for bs in 1 2 3 4 5 7 8 10 13 16 32 64 100 128 1000 1024 4096 9999 100000 10000000; do
	if ! build "$TMP/gnl_bs" "$bs" 0; then ko "BUFFER_SIZE=$bs : ne compile pas"; continue; fi
	pass=0; first=""
	for f in "$F"/*; do
		if run_file "$TMP/gnl_bs" "$f"; then pass=$((pass + 1))
		elif [ -z "$first" ]; then first="$(basename "$f") : $MSG"; fi
	done
	if [ $pass -eq $NB ]; then ok "BUFFER_SIZE=$bs : $pass/$NB"
	else ko "BUFFER_SIZE=$bs : $pass/$NB (premier échec -> $first)"; fi
done

# ============================================================
if [ $HAS_BONUS -eq 1 ]; then
	title "7. Bonus"
	check_header "$BONUS_H"
	check_sources $BONUS_SRC
	check_objects bonus 1 $BONUS_SRC
	if build "$TMP/gnlb42" 42 1; then
		ok "bonus compile avec -D BUFFER_SIZE=42"
		pass=0; first=""
		for f in "$F"/*; do
			if run_file "$TMP/gnlb42" "$f"; then pass=$((pass + 1))
			elif [ -z "$first" ]; then first="$(basename "$f") : $MSG"; fi
		done
		if [ $pass -eq $NB ]; then ok "bonus, fichiers simples : $pass/$NB"
		else ko "bonus, fichiers simples : $pass/$NB (premier échec -> $first)"; fi
		for bs in 1 42 100000; do
			if build "$TMP/gnlb_bs" "$bs" 1 && multi_test "$TMP/gnlb_bs"; then
				ok "bonus multi-fd (3 fichiers en alternance), BUFFER_SIZE=$bs"
			else ko "bonus multi-fd, BUFFER_SIZE=$bs : ${MSG:-ne compile pas}"; fi
		done
		timeout $TO "$TMP/gnlb42" badfd "$F/08_deux_lignes" > /dev/null 2> "$TMP/err"; rc=$?
		if [ $rc -eq 0 ]; then ok "bonus fd invalides (-1, 4242, fermé, dossier) -> NULL"
		else ko "bonus fd invalides : $(rc_msg $rc)"; fi
	else
		ko "le bonus ne compile pas :"
		sed 's/^/        /' "$TMP/cc.log" | head -n 20
	fi
fi

# ============================================================
title "8. Valgrind"
if command -v valgrind > /dev/null 2>&1; then
	build "$TMP/gnl1" 1 0
	for f in 01_fichier_vide 06_mot_sans_nl 08_deux_lignes 19_lignes_vides_alternees 24_10000_lignes; do
		vg "BS=42 $f" "$TMP/gnl42" "$F/$f"
	done
	for f in 01_fichier_vide 06_mot_sans_nl 08_deux_lignes 19_lignes_vides_alternees; do
		vg "BS=1  $f" "$TMP/gnl1" "$F/$f"
	done
	vg "BS=42 stdin" "$TMP/gnl42" - < "$F/08_deux_lignes"
	vg "BS=42 fd invalides" "$TMP/gnl42" badfd "$F/08_deux_lignes"
	if [ $HAS_BONUS -eq 1 ] && [ -x "$TMP/gnlb42" ]; then
		mkdir -p "$TMP/multi"
		vg "bonus multi-fd" "$TMP/gnlb42" multi "$F/18_1000_lignes_courtes" "$F/09_deux_lignes_fin_sans_nl" \
			"$F/25_longueurs_1_a_200" "$TMP/multi/1" "$TMP/multi/2" "$TMP/multi/3"
		vg "bonus fd invalides" "$TMP/gnlb42" badfd "$F/08_deux_lignes"
	fi
else warn "valgrind non installé (sudo apt install valgrind)"; fi

# ============================================================
title "9. BUFFER_SIZE <= 0"
for bs in 0 -1; do
	if ! CFLAGS="-Wall -Wextra" build "$TMP/gnl_neg" "$bs" 0; then
		ko "BUFFER_SIZE=$bs : ne compile pas (tableau sur la pile ?)"; continue
	fi
	timeout $TO "$TMP/gnl_neg" "$F/08_deux_lignes" > "$TMP/out" 2> "$TMP/err"; rc=$?
	if [ $rc -eq 0 ] && [ ! -s "$TMP/out" ]; then ok "BUFFER_SIZE=$bs : renvoie NULL proprement"
	elif [ $rc -eq 0 ]; then ko "BUFFER_SIZE=$bs : renvoie des lignes au lieu de NULL"
	else ko "BUFFER_SIZE=$bs : $(rc_msg $rc)"; fi
done

# ============================================================
title "10. Git"
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
	ok "dépôt git détecté"
	TRACK="$MAND_SRC $MAND_H README.md"
	[ $HAS_BONUS -eq 1 ] && TRACK="$TRACK $BONUS_SRC $BONUS_H"
	for f in $TRACK; do
		if git ls-files --error-unmatch "$f" > /dev/null 2>&1; then ok "$f suivi par git"
		else ko "$f pas ajouté (git add $f)"; fi
	done
	st=$(git status --porcelain)
	if [ -z "$st" ]; then ok "rien à commit"
	else warn "modifications non commitées :"; echo "$st" | head -n 10 | sed 's/^/        /'; fi
	extra=$(git ls-files | grep -Ev '^(get_next_line(_utils)?(_bonus)?[.][ch]|README[.]md|[.]gitignore)$' | tr '\n' ' ')
	[ -n "$extra" ] && warn "fichiers en trop dans le dépôt : $extra"
	git status -sb 2>/dev/null | head -n 1 | grep -q 'ahead' && warn "des commits ne sont pas encore push"
else warn "pas un dépôt git"; fi

# ============================================================
title "11. README.md"
if [ -f README.md ]; then
	ok "README.md présent"
	if head -n 1 README.md | grep -qi "42 curriculum"; then ok "1re ligne : mention du cursus 42"
	else ko "1re ligne attendue : *This project has been created as part of the 42 curriculum by <login>.*"; fi
	if head -n 1 README.md | grep -q '^[*_].*[*_][[:space:]]*$'; then ok "1re ligne en italique"
	else warn "1re ligne pas en italique"; fi
	for s in Description Instructions Resources; do
		if grep -Eqi "^#+.*$s" README.md; then ok "section $s"; else ko "section $s manquante"; fi
	done
	if grep -Eqi '(^|[^a-z])(ai|ia)([^a-z]|$)' README.md; then ok "usage de l'IA mentionné"
	else ko "le README doit décrire l'usage de l'IA"; fi
else ko "README.md manquant (obligatoire)"; fi

# ============================================================
title "BILAN"
printf "  ${G}%d OK${N}   ${R}%d KO${N}   ${Y}%d WARN${N}\n" $PASS $FAIL $WARN
if [ $HAS_MAIN -eq 1 ]; then
	printf "\n  ${Y}${BD}ATTENTION : un main non commenté traîne dans tes sources, retire-le avant de push.${N}\n"
fi
if [ $FAIL -eq 0 ]; then printf "\n  ${G}${BD}Tout est bon, prêt pour le rendu !${N}\n\n"
else printf "\n  ${R}${BD}Il reste des KO à corriger.${N}\n\n"; fi
[ $FAIL -eq 0 ]
