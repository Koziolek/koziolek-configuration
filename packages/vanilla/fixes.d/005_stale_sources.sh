#!/usr/bin/env bash
# Fix `stale-sources`: martwe źródło apt `docker.list` na Vanilli, gdzie Docker nie jest zainstalowany.
# Sourcowane przez runner (packages/commons/fixes_runner.sh), niczego nie wykonuje przy source'owaniu.
# Fix dotyczy tylko Vanilli, więc leży w jej katalogu (packages/vanilla/fixes.d/).
#
# Subsystem `apx` używa podmana, a `docker.list` (suite `orchid` -> 404) zostaje po poprzednich
# konfiguracjach i zaśmieca każdy `apt-get update` ostrzeżeniami. Usunięcie plików z /etc to
# ingerencja poza HOME, więc FIX_RISK=high: `apply` tylko z `--allow-high` (świadoma zgoda
# człowieka, nigdy z crona). Samo wykrycie jest bezpieczne i trafia do raportu `--check`.
#
# Ścieżki z /etc można przekierować (testy): FIX_APT_SOURCES_DIR, FIX_APT_KEYRINGS_DIR.

FIX_ID=stale-sources
FIX_DESC="martwe źródło apt docker.list, a Docker nie jest zainstalowany (Vanilla używa podmana)"
FIX_PHASE="pre-apt"
FIX_CONTEXTS=vanilla
FIX_NEEDS_ROOT=1
FIX_RISK=high

_stale_sources_list() { printf '%s/docker.list' "${FIX_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"; }
_stale_sources_key() { printf '%s/docker.gpg' "${FIX_APT_KEYRINGS_DIR:-/etc/apt/keyrings}"; }

fix_detect() {
    [ -f "$(_stale_sources_list)" ] || return 1
    command -v docker >/dev/null 2>&1 && return 1
    fix_detail "docker.list bez zainstalowanego Dockera"
    return 0
}

fix_apply() {
    fix_log "usuwam %s i %s" "$(_stale_sources_list)" "$(_stale_sources_key)"
    $SUDO rm -f "$(_stale_sources_list)" "$(_stale_sources_key)" || return 1
    $SUDO apt-get -qq update >/dev/null 2>&1 || true
    return 0
}

fix_verify() {
    [ ! -e "$(_stale_sources_list)" ]
}
