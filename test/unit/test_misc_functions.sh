#!/usr/bin/env bash
# Testy jednostkowe: bash/functions.d/095_function_misc.sh
# Zakres: generate_month_dirs, weather (install_lib testowany osobno)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# WORKSPACE_TOOLS musi być ustawiony zanim 095 zostanie wsourcowany
# (używany przez install_lib, nie przez testowane tu funkcje)
export WORKSPACE_TOOLS="${WORKSPACE_TOOLS:-/tmp/fake_workspace_tools_$$}"

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/095_function_misc.sh"

# ---------------------------------------------------------------------------

_ORIG_DIR=''
_TEMP_DIR=''

oneTimeSetUp() {
    _ORIG_DIR="$(pwd)"
}

oneTimeTearDown() {
    cd "$_ORIG_DIR" || true
}

setUp() {
    _TEMP_DIR="$(mktemp -d)"
    cd "$_TEMP_DIR" || return 1
}

tearDown() {
    cd "$_ORIG_DIR" || true
    rm -rf "$_TEMP_DIR"
}

# ---------------------------------------------------------------------------
# generate_month_dirs
# ---------------------------------------------------------------------------

testGenerateMonthDirsCreates12Dirs() {
    generate_month_dirs >/dev/null 2>&1
    local count
    count=$(find . -maxdepth 1 -mindepth 1 -type d | wc -l)
    assertEquals 'muszą powstać dokładnie 12 katalogów' 12 "$count"
}

testGenerateMonthDirsNamingFormatFirstMonth() {
    generate_month_dirs >/dev/null 2>&1
    assertTrue '01-styczen musi istnieć' '[ -d "01-styczen" ]'
}

testGenerateMonthDirsNamingFormatLastMonth() {
    generate_month_dirs >/dev/null 2>&1
    assertTrue '12-grudzien musi istnieć' '[ -d "12-grudzien" ]'
}

testGenerateMonthDirsNamingFormatMidYear() {
    generate_month_dirs >/dev/null 2>&1
    assertTrue '06-czerwiec musi istnieć' '[ -d "06-czerwiec" ]'
    assertTrue '09-wrzesien musi istnieć' '[ -d "09-wrzesien" ]'
}

testGenerateMonthDirsSkipsExistingWithoutError() {
    mkdir -p "03-marzec"
    local rc=0
    generate_month_dirs >/dev/null 2>&1 || rc=$?
    assertEquals 'wywołanie przy istniejącym katalogu nie może zwrócić błędu' 0 "$rc"
}

testGenerateMonthDirsIdempotent() {
    generate_month_dirs >/dev/null 2>&1
    generate_month_dirs >/dev/null 2>&1
    local count
    count=$(find . -maxdepth 1 -mindepth 1 -type d | wc -l)
    assertEquals 'drugie wywołanie nie może tworzyć duplikatów' 12 "$count"
}

# ---------------------------------------------------------------------------
# weather
# ---------------------------------------------------------------------------

testWeatherRequiresCityArg() {
    local rc=0
    weather 2>/dev/null || rc=$?
    assertNotEquals 'brak argumentu musi zwrócić kod błędu' 0 "$rc"
}

testWeatherWithMockedCurl() {
    # Funkcja curl dziedziczona przez $() bez export -f
    curl() { echo "Sunny +20C 60% 10km/h"; }
    local output
    output=$(weather "Warszawa" 2>/dev/null)
    assertContains 'output musi zawierać nazwę miasta' "$output" 'Warszawa'
    assertContains 'output musi zawierać sekcję Temperature' "$output" 'Temperature'
    unset -f curl
}

testWeatherFailsWhenCurlReturnsEmpty() {
    curl() { echo ""; }
    local rc=0
    weather "Warszawa" >/dev/null 2>&1 || rc=$?
    assertNotEquals 'pusta odpowiedź curl musi zwrócić kod błędu' 0 "$rc"
    unset -f curl
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
