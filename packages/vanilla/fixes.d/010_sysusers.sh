#!/usr/bin/env bash
# Fix `sysusers`: pakiety spakowane z sysusers.d w nowszej składni, niż obsługuje zainstalowany
# `systemd-sysusers`. Sourcowane przez runner (packages/commons/fixes_runner.sh), niczego nie
# wykonuje przy source'owaniu. Dotyczy tylko Vanilli (kontener apx, baza Debian sid), więc leży
# w packages/vanilla/fixes.d/.
#
# Pakiety bywają spakowane z sysusers.d, który używa modyfikatora `!` (np. `u!`, dodany w systemd
# 257 — tak ma pcscd >= 2.5.2), a binarka sysusers jest starsza. Kontener apx ma tylko minimalny
# `systemd-standalone-sysusers`, a nic w `Depends:` pcscd nie wymusza jego wersji, więc apt nie
# podciąga go sam. Rozjazd psuje postinst ("Unknown modifier 'u!'").
#
# Zwykłe `apt-get install --only-upgrade` nie wystarcza: skoro pcscd raz padł, apt przy KAŻDYM
# kolejnym wywołaniu najpierw sam próbuje domknąć half-configured pcscd (ten sam błąd, zanim
# podciągnie nowszy sysusers). Obejście: goły `dpkg -i` z konkretnym plikiem konfiguruje TYLKO ten
# pakiet — nowszy sysusers ląduje skonfigurowany PRZED jakimkolwiek `apt-get install`/`full-upgrade`.
#
# Wykrycie (tylko odczyt, bez sieci): dodatni dowód = zainstalowany `systemd-sysusers` ma wersję
# główną < 257 ORAZ któryś plik w sysusers.d używa modyfikatora `!`. Samo to, że w repo jest nowszy
# sysusers, NIE jest awarią (inaczej każda zwykła aktualizacja świeciłaby na czerwono w monitoringu).
# Faza post-update: apply potrzebuje świeżego indeksu apt (`apt-get download`).
#
# Ścieżkę sysusers.d można przekierować (testy): FIX_SYSUSERS_DIR.

FIX_ID=sysusers
FIX_DESC="systemd-sysusers starszy niż 257, a pakiety używają modyfikatora ! w sysusers.d (Unknown modifier 'u!')"
FIX_PHASE="post-update"
FIX_CONTEXTS=vanilla
FIX_NEEDS_ROOT=1
FIX_RISK=low

_SYSUSERS_MIN_MAJOR=257

# _sysusers_major — wersja główna zainstalowanego systemd-sysusers na stdout; kod 1 gdy się nie da.
_sysusers_major() {
    local line major
    line=$(systemd-sysusers --version 2>/dev/null | head -n1) || return 1
    major=$(printf '%s\n' "$line" | awk '$1 == "systemd" && $2 ~ /^[0-9]+$/ {print $2}')
    [ -n "$major" ] || return 1
    printf '%s' "$major"
}

# _sysusers_offenders — pliki sysusers.d z modyfikatorem `!` w typie wpisu (np. `u!`).
_sysusers_offenders() {
    local dir="${FIX_SYSUSERS_DIR:-/usr/lib/sysusers.d}"
    [ -d "$dir" ] || return 0
    grep -lE '^[A-Za-z][-+!]*![-+!]*[[:space:]]' "$dir"/*.conf 2>/dev/null | xargs -r -n1 basename
}

# _sysusers_skew — 0 gdy jest dodatni dowód rozjazdu; 1 gdy zdrowo; 3 gdy nie da się ustalić.
_sysusers_skew() {
    local major offenders
    major=$(_sysusers_major) || return 3
    [ "$major" -lt "$_SYSUSERS_MIN_MAJOR" ] || return 1
    offenders=$(_sysusers_offenders | tr '\n' ' ')
    offenders="${offenders% }"
    [ -n "$offenders" ] || return 1
    fix_detail "systemd-sysusers $major < $_SYSUSERS_MIN_MAJOR, modyfikator ! w: $offenders"
    return 0
}

fix_detect() {
    command -v systemd-sysusers >/dev/null 2>&1 || return 2
    _sysusers_skew
}

fix_apply() {
    local sysusers_bin owner_pkg tmp_dir rc=0
    sysusers_bin=$(command -v systemd-sysusers 2>/dev/null) || return 1
    owner_pkg=$(dpkg -S "$sysusers_bin" 2>/dev/null | cut -d: -f1 | head -n1)
    [ -n "$owner_pkg" ] || {
        fix_log "nie ustalono pakietu właściciela %s" "$sysusers_bin"
        return 1
    }

    tmp_dir=$(mktemp -d) || return 1
    (
        cd "$tmp_dir" || exit 1
        $SUDO apt-get download "$owner_pkg" >/dev/null 2>&1 || {
            fix_log "apt-get download %s nie powiodło się" "$owner_pkg"
            exit 1
        }
        $SUDO dpkg -i "${owner_pkg}"_*.deb >/dev/null 2>&1 || {
            fix_log "dpkg -i %s nie powiodło się" "$owner_pkg"
            exit 1
        }
    ) || rc=1
    rm -rf "$tmp_dir"
    return $rc
}

fix_verify() {
    ! _sysusers_skew
}
