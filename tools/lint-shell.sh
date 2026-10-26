#!/usr/bin/env bash
# lint-shell.sh — sprawdza i formatuje skrypty powłoki przez linthis (ShellCheck + shfmt).
#
# Samodzielny: nie zależy od niczego z tego repozytorium, więc można go skopiować do innego projektu.
# Konfigurację bierze z projektu: .shellcheckrc (ShellCheck) i .editorconfig (shfmt: wcięcie itd.).
#
# Użycie: tools/lint-shell.sh [--check | --format] [--all | --base REF] [--] [PLIK…]
#   (bez opcji)  formatowanie + sprawdzanie (format zmienia pliki w miejscu!)
#   --check      tylko sprawdzanie ShellCheck, pliki niezmienione
#   --format     tylko formatowanie shfmt
#   --all        wszystkie śledzone przez git pliki *.sh i *.bash
#   --base REF   zmienione względem REF (domyślnie: merge-base z gałęzią domyślną origin)
#   PLIK…        konkretne pliki (pomija wybór zakresu)
#
# Bez PLIK… i --all zakres to pliki *.sh/*.bash zmienione względem gałęzi domyślnej (commity,
# zmiany w working tree i nowe niezignorowane) — całe repo nie zostanie przeformatowane przypadkiem.
#
# Kody wyjścia: 0 ok (uwagi ShellCheck o wadze info/style są wypisywane, ale nie wyłączają); 1 linthis
# znalazł błędy (error); 2 linthis znalazł ostrzeżenia (warning) — kody 1 i 2 pochodzą od linthis;
# 64 zły argument lub środowisko; 127 brak linthis/shellcheck/shfmt.

set -u

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//; /^$/d'
}

die() {
    echo "lint-shell: $*" >&2
    exit 64
}

do_check=0
do_format=0
all=0
base=""
files=()

while [ "$#" -gt 0 ]; do
    case "$1" in
    --check) do_check=1 ;;
    --format) do_format=1 ;;
    --all) all=1 ;;
    --base)
        [ "$#" -ge 2 ] || die "--base wymaga argumentu"
        base="$2"
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    --)
        shift
        files+=("$@")
        break
        ;;
    -*) die "nieznana opcja: $1 (pomoc: --help)" ;;
    *) files+=("$1") ;;
    esac
    shift
done

# brak --check i --format = oba
if [ "$do_check" -eq 0 ] && [ "$do_format" -eq 0 ]; then
    do_check=1
    do_format=1
fi

missing=()
for tool in linthis shellcheck shfmt; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "lint-shell: brak w PATH: ${missing[*]}" >&2
    echo "  Zainstaluj: linthis przez 'cargo install --locked linthis', shfmt przez 'go install mvdan.cc/sh/v3/cmd/shfmt@latest'," >&2
    echo "  ShellCheck przez 'cabal install ShellCheck' (albo menedżer pakietów systemu)." >&2
    echo "  W koziolek-configuration robią to packages/<system>/install.sh i update.sh (lista: packages/commons/lang_packages.sh)." >&2
    exit 127
fi

if [ "${#files[@]}" -gt 0 ]; then
    for f in "${files[@]}"; do
        [ -f "$f" ] || die "nie ma pliku: $f"
    done
else
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "to nie jest repozytorium git (podaj PLIK…)"
    cd "$root" || die "nie można wejść do $root"

    if [ "$all" -eq 1 ]; then
        while IFS= read -r -d '' f; do files+=("$f"); done < <(git ls-files -z -- '*.sh' '*.bash')
    else
        if [ -z "$base" ]; then
            for ref in "$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)" origin/main origin/master main master; do
                if [ -n "$ref" ] && git rev-parse -q --verify "$ref" >/dev/null 2>&1; then
                    base="$ref"
                    break
                fi
            done
        fi
        if [ -n "$base" ] && mb="$(git merge-base HEAD "$base" 2>/dev/null)"; then
            :
        else
            echo "lint-shell: nie znaleziono gałęzi bazowej — biorę tylko zmiany względem HEAD" >&2
            mb="HEAD"
        fi
        # zmienione (commity + working tree) oraz nowe, niezignorowane; sort -zu usuwa duplikaty
        while IFS= read -r -d '' f; do
            [ -f "$f" ] && files+=("$f")
        done < <({
            git diff -z --name-only --diff-filter=ACMR "$mb" -- '*.sh' '*.bash'
            git ls-files -z --others --exclude-standard -- '*.sh' '*.bash'
        } | sort -zu)
    fi
fi

if [ "${#files[@]}" -eq 0 ]; then
    echo "lint-shell: brak plików .sh do sprawdzenia"
    exit 0
fi

args=(--lang shell --checks lint --no-save-result)
[ "$do_check" -eq 1 ] && [ "$do_format" -eq 0 ] && args+=(--check-only)
[ "$do_format" -eq 1 ] && [ "$do_check" -eq 0 ] && args+=(--format-only)
for f in "${files[@]}"; do
    args+=(-i "$f")
done

echo "lint-shell: ${#files[@]} plik(ów)"
linthis "${args[@]}"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "lint-shell: linthis zakończył się kodem $rc" >&2
fi
exit "$rc"
