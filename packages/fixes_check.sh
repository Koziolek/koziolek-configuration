#!/usr/bin/env bash
# Wejście dla crona/monitoringu do rejestru napraw (#144): funkcje tylko do ODCZYTU stanu. Sourcowane
# (`. packages/fixes_check.sh; fixes_check`) albo uruchamiane wprost (`bash packages/fixes_check.sh [opcje]`
# = `fixes_check "$@"`). Nie zakłada żadnych reguł cron — to wołający (np. `cron_add`) wybiera harmonogram.
#
# Zawsze `run_fixes --check`: bez `fix_apply`, bez roota i sieci, bez pytań i TTY, z `timeout` na każdy fix.
# `FIX_RISK=high` i naprawy w ogóle zostają w `update_*` pod okiem człowieka.
#
#     fixes_check [faza|all] [--only id,…] [--format text|tsv|json]     (domyślnie: all, tsv)
#
# Kod wyjścia (jak `run_fixes --check`): 0 = zdrowo, 10 = wykryto problem, 11 = nieudane,
# 12 = tylko unknown/skipped (brak danych — nie alarm), 2 = błędne wywołanie.
# Wynik na stdout (cron przekierowuje do logu); komunikaty diagnostyczne fixów na stderr.
#
# Zmienne: FIXES_DIRS (nadpisuje wyliczone katalogi rejestru), FIXES_TIMEOUT (s na wywołanie, domyślnie 120),
# FIXES_CONTEXT / CONFIG_CONTEXT_FORCE (kontekst; domyślnie wykrywany — cron nie ma $CONFIG_CONTEXT),
# FIX_APT_UPDATE_LOG (log `apt-get update` dla fixa `apt-gpg`; bez niego stan to `unknown`, nie `ok`).
_FIXES_CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/commons/fixes_runner.sh
. "$_FIXES_CHECK_DIR/commons/fixes_runner.sh"
# shellcheck source=bash/contexts/detect.sh
. "$_FIXES_CHECK_DIR/../bash/contexts/detect.sh"

# fixes_check_dirs — katalogi rejestru dla bieżącego systemu (rozdzielone `:`): commons/fixes.d plus
# packages/<system>/fixes.d, jeśli istnieje (jak FIXES_DIRS w vanilla/update.sh). Nieobsługiwany kontekst
# = same commons.
fixes_check_dirs() {
    local dirs="$_FIXES_CHECK_DIR/commons/fixes.d" ctx suffix
    ctx="${FIXES_CONTEXT:-${CONFIG_CONTEXT:-$(detect_context)}}"
    if suffix="$(context_package_suffix "$ctx" 2>/dev/null)" && [ -d "$_FIXES_CHECK_DIR/$suffix/fixes.d" ]; then
        dirs="$dirs:$_FIXES_CHECK_DIR/$suffix/fixes.d"
    fi
    printf '%s\n' "$dirs"
}

# fixes_check [faza|all] [--only id,…] [--format text|tsv|json] — raport stanu napraw, kod jak run_fixes --check.
fixes_check() {
    local phase=all fmt=tsv
    local -a extra=()
    case "${1:-}" in
        pre-apt|post-update|post-apt|all) phase="$1"; shift ;;
    esac
    while [ $# -gt 0 ]; do
        case "$1" in
            --format) fmt="${2:-}"; shift ;;
            --format=*) fmt="${1#*=}" ;;
            --only) extra+=(--only "${2:-}"); shift ;;
            --only=*) extra+=("$1") ;;
            *) echo "fixes_check: nieznany argument '$1'" >&2; return 2 ;;
        esac
        shift
    done
    local ctx
    ctx="${FIXES_CONTEXT:-${CONFIG_CONTEXT:-$(detect_context)}}"
    FIXES_CONTEXT="$ctx" FIXES_DIRS="${FIXES_DIRS:-$(fixes_check_dirs)}" \
        run_fixes "$phase" --check --format "$fmt" ${extra[@]+"${extra[@]}"} </dev/null
}

# Uruchomienie wprost (nie przez source) — cienki punkt wejścia dla `cron_add`.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    fixes_check "$@"
fi
