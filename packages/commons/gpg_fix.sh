#!/usr/bin/env bash
# Cienki wrapper refresh_apt_gpg_keys dla ubuntu/update.sh i vanilla/update.sh.
# Sourcowane, nie wykonywane. Logika siedzi w rejestrze napraw: fixes.d/020_apt_gpg.sh (#144) —
# wykrywanie z logu `apt-get update` (bez sieci w samym `fix_detect`), naprawa osobno.
# Wersja NIEINTERAKTYWNA; odpowiednik dla powłoki to bash/functions.d/096_function_apt_trust.sh
# (decyzja z #144: dwie implementacje zostają, różnią się UX — patrz nagłówek fixa).
#
# Wrapper robi jeden `apt-get update` (log w FIX_APT_UPDATE_LOG, domyślnie
# ~/.cache/koziolek-configuration/apt-update.log — z niego korzysta też `run_fixes --check`),
# potem `run_fixes pre-apt --only apt-gpg` i tłumaczy raport na ok/warn oraz tablicę REPOS_DEAD.
#
# Wymaga od skryptu wołającego zdefiniowanych (przed WYWOŁANIEM, nie przed source'owaniem):
# $SUDO, funkcji ok()/warn()/info(), tablicy REPOS_DEAD. Zawsze `return 0`.
_GPG_FIX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/commons/fixes_runner.sh
. "$_GPG_FIX_DIR/fixes_runner.sh"

refresh_apt_gpg_keys() {
    info "Sprawdzanie kluczy GPG repozytoriów apt..."
    local log="${FIX_APT_UPDATE_LOG:-${XDG_CACHE_HOME:-$HOME/.cache}/koziolek-configuration/apt-update.log}"
    mkdir -p "$(dirname "$log")" 2>/dev/null || true
    $SUDO apt-get update >"$log" 2>&1 || true

    local out line id state phase risk detail
    # Apply z kluczami z keyservera i `apt-get update` potrafi trwać dłużej niż domyślne 120 s.
    if [ "${SUDO+x}" = x ]; then
        out=$(FIX_APT_UPDATE_LOG="$log" FIXES_TIMEOUT="${FIXES_TIMEOUT:-900}" FIXES_SUDO="$SUDO" \
            run_fixes pre-apt --only apt-gpg --format tsv) || true
    else
        out=$(FIX_APT_UPDATE_LOG="$log" FIXES_TIMEOUT="${FIXES_TIMEOUT:-900}" \
            run_fixes pre-apt --only apt-gpg --format tsv) || true
    fi

    while IFS= read -r line; do
        case "$line" in
            '#dead_repo'$'\t'*) REPOS_DEAD+=("${line#*$'\t'}") ;;
            '#'*|'') ;;
            *)
                IFS=$'\t' read -r id state phase risk detail <<<"$line"
                case "$state" in
                    ok) ok "Klucze GPG w porządku" ;;
                    fixed) ok "Klucze GPG naprawione" ;;
                    na) ;;
                    *) warn "Klucze GPG (${state}): ${detail:-sprawdź ręcznie: sudo apt-get update}" ;;
                esac
                ;;
        esac
    done <<<"$out"
    return 0
}
