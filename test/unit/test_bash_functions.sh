#!/usr/bin/env bash
# Testy jednostkowe: reload_config (bash/bash_functions.sh)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"

# Wyciągnij definicję reload_config bez uruchamiania reszty pliku
eval "$(awk '/^function reload_config/,/^\}$/' "$PROJECT_ROOT/bash/bash_functions.sh")"

_LOG_MESSAGES=()
_ORIG_MAIN_DIR=''
_TMP_DIR=''

log_info()  { _LOG_MESSAGES+=("INFO: $*"); }
log_error() { _LOG_MESSAGES+=("ERROR: $*"); }
log_warn()  { _LOG_MESSAGES+=("WARN: $*"); }

oneTimeSetUp() {
    _ORIG_MAIN_DIR="${MAIN_CONFIGURATION_DIR:-}"
}

oneTimeTearDown() {
    export MAIN_CONFIGURATION_DIR="$_ORIG_MAIN_DIR"
}

setUp() {
    _LOG_MESSAGES=()
    _TMP_DIR="$(mktemp -d)"
}

tearDown() {
    rm -rf "$_TMP_DIR"
    unset BASH_FUNCTIONS_LOADED
}

# ---------------------------------------------------------------------------
# Walidacja wejścia
# ---------------------------------------------------------------------------

testMissingMainConfigDirReturnsOne() {
    unset MAIN_CONFIGURATION_DIR
    local rc=0
    reload_config 2>/dev/null || rc=$?
    assertNotEquals 'brak MAIN_CONFIGURATION_DIR musi zwrócić kod błędu' 0 "$rc"
}

testMissingMainConfigDirLogsError() {
    unset MAIN_CONFIGURATION_DIR
    _LOG_MESSAGES=()
    reload_config 2>/dev/null || true
    assertEquals 'brak MAIN_CONFIGURATION_DIR musi logować błąd' \
        "ERROR: MAIN_CONFIGURATION_DIR is not set — cannot reload" "${_LOG_MESSAGES[0]:-}"
}

testEmptyMainConfigDirReturnsOne() {
    export MAIN_CONFIGURATION_DIR=""
    local rc=0
    reload_config 2>/dev/null || rc=$?
    assertNotEquals 'pusty MAIN_CONFIGURATION_DIR musi zwrócić kod błędu' 0 "$rc"
}

testEmptyMainConfigDirLogsError() {
    export MAIN_CONFIGURATION_DIR=""
    _LOG_MESSAGES=()
    reload_config 2>/dev/null || true
    assertEquals 'pusty MAIN_CONFIGURATION_DIR musi logować błąd' \
        "ERROR: MAIN_CONFIGURATION_DIR is not set — cannot reload" "${_LOG_MESSAGES[0]:-}"
}

testMissingMainShReturnsOne() {
    export MAIN_CONFIGURATION_DIR="/tmp/nieistniejacy_katalog_$$"
    local rc=0
    reload_config 2>/dev/null || rc=$?
    assertNotEquals 'brak main.sh musi zwrócić kod błędu' 0 "$rc"
}

testMissingMainShLogsError() {
    export MAIN_CONFIGURATION_DIR="/tmp/nieistniejacy_katalog_$$"
    _LOG_MESSAGES=()
    reload_config 2>/dev/null || true
    assertEquals 'brak main.sh musi logować błąd' \
        "ERROR: main.sh not found: /tmp/nieistniejacy_katalog_$$/main.sh" "${_LOG_MESSAGES[0]:-}"
}

testMainShIsDirectoryReturnsOne() {
    mkdir -p "$_TMP_DIR/main.sh"
    export MAIN_CONFIGURATION_DIR="$_TMP_DIR"
    local rc=0
    reload_config 2>/dev/null || rc=$?
    assertNotEquals 'main.sh jako katalog musi zwrócić kod błędu' 0 "$rc"
}

testMainShIsDirectoryLogsError() {
    mkdir -p "$_TMP_DIR/main.sh"
    export MAIN_CONFIGURATION_DIR="$_TMP_DIR"
    _LOG_MESSAGES=()
    reload_config 2>/dev/null || true
    assertEquals 'main.sh jako katalog musi logować błąd' \
        "ERROR: main.sh not found: $_TMP_DIR/main.sh" "${_LOG_MESSAGES[0]:-}"
}

# ---------------------------------------------------------------------------
# Poprawne wykonanie
# ---------------------------------------------------------------------------

testSuccessfulReloadReturnsZero() {
    printf '' > "$_TMP_DIR/main.sh"
    export MAIN_CONFIGURATION_DIR="$_TMP_DIR"
    local rc=99
    reload_config 2>/dev/null; rc=$?
    assertEquals 'poprawny reload musi zwrócić 0' 0 "$rc"
}

testSuccessfulReloadSourcesMainSh() {
    local marker="$_TMP_DIR/sourced"
    export SOURCED_MARKER="$marker"
    printf 'touch "${SOURCED_MARKER}"\n' > "$_TMP_DIR/main.sh"
    export MAIN_CONFIGURATION_DIR="$_TMP_DIR"
    reload_config 2>/dev/null
    assertTrue 'main.sh musi być faktycznie sourcowany' "[ -f '$marker' ]"
    unset SOURCED_MARKER
}

testSuccessfulReloadLogsInfo() {
    printf '' > "$_TMP_DIR/main.sh"
    export MAIN_CONFIGURATION_DIR="$_TMP_DIR"
    _LOG_MESSAGES=()
    reload_config 2>/dev/null
    assertEquals 'poprawny reload musi logować info' \
        "INFO: Konfiguracja przeładowana z $_TMP_DIR/main.sh" "${_LOG_MESSAGES[0]:-}"
}

testVariablesFromMainShVisibleAfterReload() {
    printf 'export RELOAD_TEST_VAR="hello_from_reload"\n' > "$_TMP_DIR/main.sh"
    export MAIN_CONFIGURATION_DIR="$_TMP_DIR"
    unset RELOAD_TEST_VAR
    reload_config 2>/dev/null
    assertEquals 'zmienne z main.sh muszą być widoczne po reload' \
        'hello_from_reload' "${RELOAD_TEST_VAR:-}"
    unset RELOAD_TEST_VAR
}

# ---------------------------------------------------------------------------
# Reset flag
# ---------------------------------------------------------------------------

testBashFunctionsLoadedClearedBeforeSource() {
    local reset_marker="$_TMP_DIR/reset_check"
    export RESET_MARKER="$reset_marker"
    printf '[[ -z "$BASH_FUNCTIONS_LOADED" ]] && touch "${RESET_MARKER}"\n' > "$_TMP_DIR/main.sh"
    export MAIN_CONFIGURATION_DIR="$_TMP_DIR"
    export BASH_FUNCTIONS_LOADED=1
    reload_config 2>/dev/null
    assertTrue 'BASH_FUNCTIONS_LOADED musi być skasowane przed sourcowaniem' "[ -f '$reset_marker' ]"
    unset RESET_MARKER
}

# ---------------------------------------------------------------------------
# Obsługa błędów sourcowania
# ---------------------------------------------------------------------------

testFailingMainShReturnsOne() {
    printf 'return 1\n' > "$_TMP_DIR/main.sh"
    export MAIN_CONFIGURATION_DIR="$_TMP_DIR"
    local rc=0
    reload_config 2>/dev/null || rc=$?
    assertNotEquals 'main.sh z return 1 musi zwrócić kod błędu' 0 "$rc"
}

testFailingMainShLogsError() {
    printf 'return 1\n' > "$_TMP_DIR/main.sh"
    export MAIN_CONFIGURATION_DIR="$_TMP_DIR"
    _LOG_MESSAGES=()
    reload_config 2>/dev/null || true
    assertEquals 'main.sh z return 1 musi logować błąd' \
        "ERROR: Błąd podczas ładowania $_TMP_DIR/main.sh" "${_LOG_MESSAGES[0]:-}"
}

testFailingMainShDoesNotLogInfo() {
    printf 'return 1\n' > "$_TMP_DIR/main.sh"
    export MAIN_CONFIGURATION_DIR="$_TMP_DIR"
    _LOG_MESSAGES=()
    reload_config 2>/dev/null || true
    assertNull 'main.sh z błędem nie może logować info' "${_LOG_MESSAGES[1]:-}"
}

# ---------------------------------------------------------------------------
# Idempotentność
# ---------------------------------------------------------------------------

testMultipleReloadsCallMainShEachTime() {
    local count_file="$_TMP_DIR/count"
    echo "0" > "$count_file"
    export COUNT_FILE="$count_file"
    printf 'n=$(cat "$COUNT_FILE"); echo $((n+1)) > "$COUNT_FILE"\n' > "$_TMP_DIR/main.sh"
    export MAIN_CONFIGURATION_DIR="$_TMP_DIR"
    reload_config 2>/dev/null
    reload_config 2>/dev/null
    reload_config 2>/dev/null
    assertEquals 'trzy reloady muszą wywołać main.sh trzy razy' '3' "$(cat "$count_file")"
    unset COUNT_FILE
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
