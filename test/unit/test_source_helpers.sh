#!/usr/bin/env bash
# Testy jednostkowe: source_if_exists, source_directory (bash/bash_functions.sh)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"

_FAKE_DIR=''
_TEST_DIR=''

oneTimeSetUp() {
    _FAKE_DIR="$(mktemp -d)"
    mkdir -p "$_FAKE_DIR/functions.d"
    export BASH_CONFIGURATION_DIR="$_FAKE_DIR"
    # shellcheck source=/dev/null
    . "$PROJECT_ROOT/bash/bash_functions.sh"
}

oneTimeTearDown() {
    rm -rf "$_FAKE_DIR"
}

setUp() {
    _TEST_DIR="$(mktemp -d)"
}

tearDown() {
    rm -rf "$_TEST_DIR"
}

# ---------------------------------------------------------------------------
# source_if_exists
# ---------------------------------------------------------------------------

testSourceIfExistsSourcesExistingFile() {
    printf 'SIE_MARKER=sourced\n' > "$_TEST_DIR/myfile.sh"
    unset SIE_MARKER
    source_if_exists "myfile" "$_TEST_DIR" 2>/dev/null
    assertEquals 'source_if_exists musi sourcować istniejący plik' 'sourced' "${SIE_MARKER:-}"
    unset SIE_MARKER
}

testSourceIfExistsMissingFileReturnsZero() {
    local rc=99
    source_if_exists "nonexistent_file_xyz" "$_TEST_DIR" 2>/dev/null
    rc=$?
    assertEquals 'brak pliku nie powinien zwracać kodu błędu' 0 "$rc"
}

testSourceIfExistsNoArgsReturnsOne() {
    local rc=0
    source_if_exists 2>/dev/null || rc=$?
    assertNotEquals 'brak argumentów musi zwrócić kod błędu' 0 "$rc"
}

testSourceIfExistsNoBashConfigDirReturnsOne() {
    local saved_dir="${BASH_CONFIGURATION_DIR:-}"
    unset BASH_CONFIGURATION_DIR
    local rc=0
    source_if_exists "something" 2>/dev/null || rc=$?
    assertNotEquals 'brak BASH_CONFIGURATION_DIR i katalogu musi zwrócić błąd' 0 "$rc"
    export BASH_CONFIGURATION_DIR="$saved_dir"
}

testSourceIfExistsUsesBashConfigDirAsDefault() {
    printf 'SIE_DEFAULT_MARKER=default_ok\n' > "$BASH_CONFIGURATION_DIR/sie_default.sh"
    unset SIE_DEFAULT_MARKER
    source_if_exists "sie_default" 2>/dev/null
    assertEquals 'source_if_exists musi używać BASH_CONFIGURATION_DIR domyślnie' \
        'default_ok' "${SIE_DEFAULT_MARKER:-}"
    unset SIE_DEFAULT_MARKER
    rm -f "$BASH_CONFIGURATION_DIR/sie_default.sh"
}

# ---------------------------------------------------------------------------
# source_directory
# ---------------------------------------------------------------------------

testSourceDirectoryLoadsNumberedFiles() {
    printf 'SD_LOADED_010=yes\n' > "$_TEST_DIR/010_first.sh"
    printf 'SD_LOADED_020=yes\n' > "$_TEST_DIR/020_second.sh"
    unset SD_LOADED_010 SD_LOADED_020
    source_directory "$_TEST_DIR" 2>/dev/null
    assertEquals 'source_directory musi załadować 010_first.sh' 'yes' "${SD_LOADED_010:-}"
    assertEquals 'source_directory musi załadować 020_second.sh' 'yes' "${SD_LOADED_020:-}"
    unset SD_LOADED_010 SD_LOADED_020
}

testSourceDirectoryIgnoresNonNumberedFiles() {
    printf 'SD_IGNORED=yes\n' > "$_TEST_DIR/ignored.sh"
    printf 'SD_IGNORED_DOT=yes\n' > "$_TEST_DIR/.hidden.sh"
    unset SD_IGNORED SD_IGNORED_DOT
    source_directory "$_TEST_DIR" 2>/dev/null
    assertNull 'source_directory nie powinna ładować pliku bez prefiksu numerycznego' \
        "${SD_IGNORED:-}"
    assertNull 'source_directory nie powinna ładować ukrytych plików' \
        "${SD_IGNORED_DOT:-}"
}

testSourceDirectoryLoadsInAlphabeticalOrder() {
    printf 'SD_ORDER_LOG="${SD_ORDER_LOG:-} A"\n' > "$_TEST_DIR/010_a.sh"
    printf 'SD_ORDER_LOG="${SD_ORDER_LOG:-} B"\n' > "$_TEST_DIR/020_b.sh"
    printf 'SD_ORDER_LOG="${SD_ORDER_LOG:-} C"\n' > "$_TEST_DIR/030_c.sh"
    unset SD_ORDER_LOG
    source_directory "$_TEST_DIR" 2>/dev/null
    assertContains 'pliki muszą być ładowane w kolejności A B C' "${SD_ORDER_LOG:-}" 'A'
    # Sprawdź że A pojawia się przed B (pozycja w stringu)
    local pos_a pos_b
    pos_a="${SD_ORDER_LOG%% A*}"
    pos_b="${SD_ORDER_LOG%% B*}"
    assertTrue 'A musi być załadowane przed B' '[ "${#pos_a}" -lt "${#pos_b}" ]'
    unset SD_ORDER_LOG
}

testSourceDirectoryMissingDirReturnsOne() {
    local rc=0
    source_directory "/nonexistent_path_xyz_12345" 2>/dev/null || rc=$?
    assertNotEquals 'brak katalogu musi zwrócić kod błędu' 0 "$rc"
}

testSourceDirectoryEmptyArgReturnsOne() {
    local rc=0
    source_directory "" 2>/dev/null || rc=$?
    assertNotEquals 'pusty argument musi zwrócić kod błędu' 0 "$rc"
}

testSourceDirectoryNoArgReturnsOne() {
    local rc=0
    source_directory 2>/dev/null || rc=$?
    assertNotEquals 'brak argumentu musi zwrócić kod błędu' 0 "$rc"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
