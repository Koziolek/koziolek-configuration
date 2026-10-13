#!/usr/bin/env bash
# Uruchamiany wewnątrz kontenera e2e.
# Sourcuje tylko definicje funkcji z initial_packages*.sh (bez top-level calls)
# i wykonuje tylko bezpieczne funkcje.
#
# SCRIPT sparametryzowany przez INIT_SCRIPT — ten sam entrypoint obsługuje
# initial_packages_ubuntu.sh (domyślnie) i initial_packages_redhat.sh
# (INIT_SCRIPT=/packages/initial_packages_redhat.sh) — nazwy funkcji są identyczne.

set -euo pipefail

SCRIPT="${INIT_SCRIPT:-/packages/initial_packages_ubuntu.sh}"

# Znajdź linię z pierwszym top-level call (cd $HOME/) — sourcujemy tylko przed nią
CUTLINE=$(grep -n "^cd " "$SCRIPT" | head -1 | cut -d: -f1)
if [[ -z "$CUTLINE" ]]; then
    echo "❌ Nie znaleziono granicy funkcji w $SCRIPT"
    exit 1
fi

# Sourcowane przez plik, nie przez process substitution: initial_packages_*.sh
# lokalizuje packages/apt_packages.sh względem ${BASH_SOURCE[0]}, a process
# substitution (/dev/fd/N) łamie to dirname'owanie.
TMPSCRIPT="$(dirname "$SCRIPT")/.e2e-head-$$.sh"
head -n $((CUTLINE - 1)) "$SCRIPT" > "$TMPSCRIPT"
# shellcheck disable=SC1090
. "$TMPSCRIPT"
rm -f "$TMPSCRIPT"

echo "=== FUNCTIONS_LOADED ==="

echo "=== INSTALL_PACKAGES_START ==="
install_initial_packages
echo "=== INSTALL_PACKAGES_DONE ==="

echo "=== WORKSPACE_START ==="
prepare_workspace
echo "=== WORKSPACE_DONE ==="

echo "=== BASHRC_START ==="
prepare_bashrc
echo "=== BASHRC_DONE ==="

# Zweryfikuj że .bashrc zostało nadpisane przez template
if grep -q "koziolek-configuration" "$HOME/.bashrc" 2>/dev/null; then
    echo "=== BASHRC_CONTAINS_CONFIG ==="
fi

# git-bug: binarka + strony man + bash completion, wszystko w ~/.local (bez sudo).
# Wymaga sieci (GitHub Releases). Obrazy e2e mają man-db i bash-completion tylko na potrzeby tej weryfikacji.
echo "=== GIT_BUG_START ==="
install_git_bug
echo "=== GIT_BUG_DONE ==="

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"

[[ -x "$HOME/.local/bin/git-bug" ]] && echo "=== GIT_BUG_BINARY_OK ==="

# `man` w minimalnym obrazie Ubuntu jest podmieniony zaślepką (dywersja do man.REAL).
MAN_BIN="$(command -v man.REAL 2>/dev/null || command -v man 2>/dev/null || true)"
if [[ -n "$MAN_BIN" ]]; then
    # man dokłada ../share/man dla każdego katalogu z PATH kończącego się na /bin — bez MANPATH.
    MAN_PATH="$(PATH="$HOME/.local/bin:$PATH" MANPATH= "$MAN_BIN" -w git-bug 2>/dev/null || true)"
    if [[ "$MAN_PATH" == "$DATA_DIR/man/man1/git-bug.1"* ]]; then
        echo "=== GIT_BUG_MAN_OK ==="
    else
        echo "man -w git-bug => '${MAN_PATH}'"
    fi
    SUB_PATH="$(PATH="$HOME/.local/bin:$PATH" MANPATH= "$MAN_BIN" -w git-bug-bug 2>/dev/null || true)"
    [[ -n "$SUB_PATH" ]] && echo "=== GIT_BUG_MAN_SUBCOMMAND_OK ==="
fi

# Completion: ładowanie leniwe przez bash-completion (jak w prawdziwej powłoce), nie przez ścieżkę wprost.
COMP="$(bash --norc --noprofile -c '
    . /usr/share/bash-completion/bash_completion
    _completion_loader git-bug
    complete -p git-bug
' 2>&1 || true)"
if [[ "$COMP" == *"-F "*"git-bug"* ]]; then
    echo "=== GIT_BUG_COMPLETION_OK ==="
else
    echo "complete -p git-bug => '${COMP}'"
fi

# Drugie wywołanie: wszystko na miejscu = brak pobierania (tani no-op pod cron).
if install_git_bug | grep -q "git-bug aktualny"; then
    echo "=== GIT_BUG_IDEMPOTENT_OK ==="
fi

echo "=== ALL_DONE ==="
