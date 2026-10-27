#!/usr/bin/env bash
# Wspólny punkt wejścia naprawek dla skryptów `*/install.sh` i `*/update.sh` (#144). Sourcowane,
# nie wykonywane. Zastępuje wrappery per fix (repair_broken_dkms_packages, refresh_apt_gpg_keys,
# cleanup_stale_sources, fix_sysusers_version_skew): skrypt woła tylko
#
#     apply_fixes <pre-apt|post-update|post-apt>
#
# a co i w jakiej kolejności się uruchomi, wynika z rejestru (FIX_PHASE/FIX_CONTEXTS w fixes.d).
#
# Wymaga od skryptu wołającego (przed WYWOŁANIEM, nie przed source'owaniem): $SUDO ('' = root),
# funkcji ok()/warn()/info(); opcjonalnie tablicy REPOS_DEAD (martwe repo apt trafiają do niej do
# końcowego podsumowania) oraz FIXES_DIRS (domyślnie tylko commons/fixes.d).
#
# apply_fixes:
#   1. `run_fixes <faza> --check` (tylko odczyt) — co wykryto i jakie ryzyko;
#   2. dla naprawy z `FIX_RISK=high` pyta o zgodę `[y/N]` (domyślnie nie, brak TTY/EOF = nie) — fix
#      sam o nic nie pyta, a `--allow-high` dostają tylko te, na które użytkownik się zgodził;
#   3. `run_fixes <faza> --only <reszta>` — naprawa, raport tłumaczony na ok/warn.
# Zawsze `return 0` (nie przerywa skryptu pod `set -e`); wynik każdej naprawy jest w raporcie.
_FIXES_APPLY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/commons/fixes_runner.sh
. "$_FIXES_APPLY_DIR/fixes_runner.sh"

# fixes_refresh_apt_log — jeden `apt-get update` z zapisem do FIX_APT_UPDATE_LOG. Z tego logu korzysta
# fix `apt-gpg` (`fix_detect` nie woła apt-get update); zapisany ląduje tam też `run_fixes --check`.
fixes_refresh_apt_log() {
    local log="${FIX_APT_UPDATE_LOG:-${XDG_CACHE_HOME:-$HOME/.cache}/koziolek-configuration/apt-update.log}"
    mkdir -p "$(dirname "$log")" 2>/dev/null || true
    $SUDO apt-get update >"$log" 2>&1 || true
    export FIX_APT_UPDATE_LOG="$log"
    return 0
}

# _apply_fixes_report — czyta raport TSV runnera ze stdin i tłumaczy na ok/warn.
_apply_fixes_report() {
    local line id state risk detail
    while IFS= read -r line; do
        case "$line" in
        '#'* | '') ;;
        *)
            IFS=$'\t' read -r id state _ risk detail <<<"$line"
            case "$state" in
            ok) ok "[$id] w porządku" ;;
            na) ;;
            fixed) ok "[$id] naprawiono" ;;
            failed) warn "[$id] naprawa nieudana${detail:+: $detail}" ;;
            skipped) warn "[$id] pominięto${detail:+: $detail}" ;;
            unknown) warn "[$id] nie udało się sprawdzić${detail:+: $detail}" ;;
            *) warn "[$id] ${state}${detail:+: $detail}" ;;
            esac
            ;;
        esac
    done
}

apply_fixes() {
    local phase="${1:?apply_fixes: brak fazy}" check report line id state risk detail reply only
    local -a ids=() rows=()

    check=$(run_fixes "$phase" --check --format tsv 2>/dev/null </dev/null) || true

    # Wiersze raportu najpierw do tablicy: pytanie o zgodę ma czytać ze stdin skryptu, nie z pętli.
    while IFS= read -r line; do rows+=("$line"); done <<<"$check"

    for line in ${rows[@]+"${rows[@]}"}; do
        case "$line" in
        '#dead_repo'$'\t'*)
            declare -p REPOS_DEAD >/dev/null 2>&1 && REPOS_DEAD+=("${line#*$'\t'}")
            ;;
        '#'* | '') ;;
        *)
            IFS=$'\t' read -r id state _ risk detail <<<"$line"
            if [ "$state" = detected ] && [ "$risk" = high ]; then
                warn "[$id] wymaga zgody (ryzyko high): ${detail:-brak szczegółów}"
                reply=n
                read -r -p "Zastosować naprawę '$id'? [y/N]: " -n 1 reply || reply=n
                echo
                if [[ ! "$reply" =~ ^[YyTt]$ ]]; then
                    info "[$id] pominięto (brak zgody)"
                    continue
                fi
            fi
            ids+=("$id")
            ;;
        esac
    done

    [ "${#ids[@]}" -gt 0 ] || return 0
    only=$(
        IFS=,
        echo "${ids[*]}"
    )
    # Apply z kluczami z keyservera i `apt-get update` potrafi trwać dłużej niż domyślne 120 s.
    # --allow-high dostają wyłącznie ids po kontroli zgody powyżej. Komunikaty fixów (stderr) idą
    # na terminal na bieżąco, raport (stdout) tłumaczymy po zakończeniu.
    if [ "${SUDO+x}" = x ]; then
        report=$(FIXES_TIMEOUT="${FIXES_TIMEOUT:-900}" FIXES_SUDO="$SUDO" \
            run_fixes "$phase" --only "$only" --allow-high --format tsv </dev/null) || true
    else
        report=$(FIXES_TIMEOUT="${FIXES_TIMEOUT:-900}" \
            run_fixes "$phase" --only "$only" --allow-high --format tsv </dev/null) || true
    fi
    _apply_fixes_report <<<"$report"
    return 0
}
