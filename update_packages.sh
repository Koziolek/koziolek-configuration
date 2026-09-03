#!/usr/bin/env bash
#
# Dispatcher: wykrywa system i uruchamia właściwy packages/update_packages_<ctx>.sh.
# Do użycia w już sklonowanym repo (`./update_packages.sh`).
#
# Mapowanie kontekst → sufiks: context_package_suffix() w bash/contexts/detect.sh
# (jedyne źródło prawdy — patrz komentarz w initial_packages.sh, ten sam wzorzec).
#
# PACKAGES_DISPATCH_DRY_RUN — jeśli ustawione: wypisz wybrany skrypt i wyjdź (testy).

set -Eeuo pipefail
trap 'echo "❌ update_packages.sh: błąd w linii $LINENO"; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=bash/contexts/detect.sh
source "$SCRIPT_DIR/bash/contexts/detect.sh"

ctx="$(detect_context)"

# Vanilla: rozróżnij immutable host od subsystemu apx (patrz resolve_vanilla_subsystem).
rc=0
ctx="$(resolve_vanilla_subsystem "$ctx")" || rc=$?
if [ "$rc" -eq 2 ]; then
    echo "❌ Jesteś na immutable hoście Vanilla OS — apt/aktualizacja tu nie zadziała." >&2
    echo "   Wejdź do subsystemu:   vso shell        (albo:  apx enter)" >&2
    echo "   i ponów:   ./update_packages.sh" >&2
    exit 1
fi

if ! suffix="$(context_package_suffix "$ctx")"; then
    echo "❌ Nieobsługiwany system (kontekst: '$ctx')." >&2
    echo "   Obsługiwane: Ubuntu/Debian, macOS, Vanilla OS 2, WSL, RedHat/CentOS/Fedora." >&2
    exit 1
fi

target="$SCRIPT_DIR/packages/update_packages_${suffix}.sh"
if [ ! -f "$target" ]; then
    echo "❌ Brak $target." >&2
    exit 1
fi

echo "▶ System: $ctx  →  packages/update_packages_${suffix}.sh"

if [ -n "${PACKAGES_DISPATCH_DRY_RUN:-}" ]; then
    echo "packages/update_packages_${suffix}.sh"
    exit 0
fi

exec bash "$target" "$@"
