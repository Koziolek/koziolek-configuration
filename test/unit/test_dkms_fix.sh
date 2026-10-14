#!/usr/bin/env bash
# Testy jednostkowe: repair_broken_dkms_packages (packages/commons/dkms_fix.sh)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

setUp() {
    _TMP="$(mktemp -d)"
    _LOG="$_TMP/calls.log"
    : > "$_LOG"
    SUDO=''
    _DKMS_PRESENT=1
    _DPKG_QUERY_OUT=''
    _CONFIGURE_RC=0

    ok()   { echo "OK $*" >> "$_LOG"; }
    warn() { echo "WARN $*" >> "$_LOG"; }
    info() { :; }

    command() {
        if [ "$1" = "-v" ] && [ "$2" = "dkms" ]; then
            [ "$_DKMS_PRESENT" = 1 ]
            return
        fi
        builtin command "$@"
    }
    dpkg-query() { printf '%s' "$_DPKG_QUERY_OUT"; }
    dpkg() {
        case "$1" in
            -L) echo "/usr/src/v4l2loopback-0.12.7"; echo "/usr/src/v4l2loopback-0.12.7/Makefile"; echo "/usr/share/doc/x" ;;
            --configure) echo "DPKG --configure $2" >> "$_LOG"; return "$_CONFIGURE_RC" ;;
        esac
    }
    dkms() { echo "DKMS $*" >> "$_LOG"; }

    # shellcheck source=/dev/null
    . "$PROJECT_ROOT/packages/commons/dkms_fix.sh"
}

tearDown() {
    rm -rf "$_TMP"
}

testNothingBrokenDoesNothing() {
    _DPKG_QUERY_OUT=$'ii  v4l2loopback-dkms\nii  openrazer-driver-dkms\n'
    repair_broken_dkms_packages
    assertEquals "brak wywołań" "" "$(cat "$_LOG")"
}

testNoDkmsInstalledReturnsQuietly() {
    _DKMS_PRESENT=0
    _DPKG_QUERY_OUT=$'iF  v4l2loopback-dkms\n'
    repair_broken_dkms_packages
    assertEquals "brak wywołań" "" "$(cat "$_LOG")"
}

testBrokenPackageIsRemovedFromTreeThenConfigured() {
    _DPKG_QUERY_OUT=$'ii  openrazer-driver-dkms\niF  v4l2loopback-dkms\n'
    repair_broken_dkms_packages
    assertContains "dkms remove modułu z /usr/src" "$(cat "$_LOG")" "DKMS remove v4l2loopback/0.12.7 --all"
    assertContains "dpkg --configure pakietu" "$(cat "$_LOG")" "DPKG --configure v4l2loopback-dkms"
    assertContains "ok po naprawie" "$(cat "$_LOG")" "OK v4l2loopback-dkms skonfigurowany"
    assertNotContains "zdrowy pakiet nietknięty" "$(cat "$_LOG")" "openrazer"
}

testRemoveHappensBeforeConfigure() {
    _DPKG_QUERY_OUT=$'iF  v4l2loopback-dkms\n'
    repair_broken_dkms_packages
    assertEquals "kolejność" "DKMS remove v4l2loopback/0.12.7 --all" "$(grep -E '^(DKMS|DPKG)' "$_LOG" | head -1)"
}

testConfigureFailureWarnsButReturnsZero() {
    _DPKG_QUERY_OUT=$'iF  v4l2loopback-dkms\n'
    _CONFIGURE_RC=1
    repair_broken_dkms_packages
    assertEquals "kod wyjścia" 0 $?
    assertContains "ostrzeżenie" "$(cat "$_LOG")" "WARN Nie udało się dokończyć konfiguracji v4l2loopback-dkms"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
