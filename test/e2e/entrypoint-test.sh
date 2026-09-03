#!/usr/bin/env bash
# Uruchamiany wewnątrz kontenera e2e.
# Sourcuje tylko definicje funkcji z initial_packages*.sh (bez top-level calls)
# i wykonuje tylko bezpieczne funkcje.
#
# SCRIPT sparametryzowany przez INIT_SCRIPT — ten sam entrypoint obsługuje
# initial_packages.sh (Ubuntu, domyślnie) i initial_packages_redhat.sh
# (INIT_SCRIPT=/initial_packages_redhat.sh) — nazwy funkcji są identyczne.

set -euo pipefail

SCRIPT="${INIT_SCRIPT:-/initial_packages.sh}"

# Znajdź linię z pierwszym top-level call (cd $HOME/) — sourcujemy tylko przed nią
CUTLINE=$(grep -n "^cd " "$SCRIPT" | head -1 | cut -d: -f1)
if [[ -z "$CUTLINE" ]]; then
    echo "❌ Nie znaleziono granicy funkcji w $SCRIPT"
    exit 1
fi

# Sourcowane przez plik, nie przez process substitution: initial_packages.sh
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

echo "=== ALL_DONE ==="
