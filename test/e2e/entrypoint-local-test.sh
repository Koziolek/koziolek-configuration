#!/usr/bin/env bash
# Uruchamiany wewnątrz kontenera e2e-local.
# Projekt jest podpięty jako /project zamiast klonowany z GitHub.

set -euo pipefail

SCRIPT=/initial_packages.sh

CUTLINE=$(grep -n "^cd " "$SCRIPT" | head -1 | cut -d: -f1)
if [[ -z "$CUTLINE" ]]; then
    echo "❌ Nie znaleziono granicy funkcji w $SCRIPT"
    exit 1
fi

# shellcheck disable=SC1090
. <(head -n $((CUTLINE - 1)) "$SCRIPT")

echo "=== FUNCTIONS_LOADED ==="

# Zainstaluj pakiety systemowe (apt — wymaga sieci)
echo "=== INSTALL_PACKAGES_START ==="
install_initial_packages
echo "=== INSTALL_PACKAGES_DONE ==="

# Zamiast prepare_workspace (który klonuje z GitHub) — podepnij lokalny projekt
echo "=== WORKSPACE_LOCAL_START ==="
mkdir -p "$HOME/workspace"
ln -sfn /project "$HOME/workspace/koziolek-configuration"
ln -sfn /project "$HOME/.koziolek-configuration"
echo "=== WORKSPACE_LOCAL_DONE ==="

# Przygotuj .bashrc z lokalnego szablonu
echo "=== BASHRC_START ==="
prepare_bashrc
echo "=== BASHRC_DONE ==="

if grep -q "koziolek-configuration" "$HOME/.bashrc" 2>/dev/null; then
    echo "=== BASHRC_CONTAINS_CONFIG ==="
fi

# Weryfikuj składnię kluczowych plików bash (bash -n nie wykonuje, tylko parsuje)
echo "=== SYNTAX_CHECK_START ==="
SYNTAX_OK=true
for f in /project/bash/functions.d/[0-9]*.sh \
         /project/bash/bash_aliases.sh \
         /project/bash/bash_exports.sh \
         /project/bash/bash_completion.sh; do
    [[ -f "$f" ]] || continue
    if ! bash -n "$f" 2>/dev/null; then
        echo "SYNTAX_FAIL: $f"
        SYNTAX_OK=false
    fi
done
$SYNTAX_OK && echo "=== SYNTAX_CHECK_DONE ==="

# Weryfikuj kluczowe pliki i katalogi w podpiętym projekcie
echo "=== STRUCTURE_CHECK_START ==="
for path in \
    /project/main.sh \
    /project/bash/main.sh \
    /project/git/main.sh \
    /project/services/main.sh \
    /project/bash/functions.d \
    /project/bash/functions.d/gab_plugins \
    /project/git/aliases \
    /project/git/hook; do
    if [[ ! -e "$path" ]]; then
        echo "MISSING: $path"
    fi
done
echo "=== STRUCTURE_CHECK_DONE ==="

echo "=== ALL_DONE ==="
