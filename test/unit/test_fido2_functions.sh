#!/usr/bin/env bash
# Testy jednostkowe: bash/functions.d/150_function_fido2.sh
#   _fido2_resolve_device (wybór urządzenia: argument / auto / interaktywne menu)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/150_function_fido2.sh"

# ---------------------------------------------------------------------------

testResolveDeviceExplicitArgSkipsDetection() {
    # jawnie podane urządzenie — nie woła detekcji, nie pyta
    _fido2_all_devices() { echo "SHOULD_NOT_BE_CALLED"; }
    local out
    out=$(_fido2_resolve_device /dev/hidraw9)
    assertEquals '/dev/hidraw9' "$out"
    unset -f _fido2_all_devices
}

testResolveDeviceSingleDetectedUsedWithoutPrompt() {
    # jeden wykryty klucz — użyj go wprost, bez interakcji
    _fido2_all_devices() { echo "/dev/hidraw3"; }
    local out
    out=$(_fido2_resolve_device 2>/dev/null)
    assertEquals '/dev/hidraw3' "$out"
    unset -f _fido2_all_devices
}

testResolveDeviceNoneDetectedFails() {
    # log_error (jak w całym repo) pisze na stdout, nie stderr — funkcja
    # zwraca kod 1; nie zakładamy pustego stdout, tylko brak sukcesu.
    _fido2_all_devices() { :; }
    local rc
    _fido2_resolve_device >/dev/null 2>&1
    rc=$?
    assertEquals 1 "$rc"
    unset -f _fido2_all_devices
}

testResolveDeviceMultiplePromptsAndPicksByNumber() {
    # kilka kluczy — menu na stderr, wybór po numerze, stdout tylko ze ścieżką
    _fido2_all_devices() { echo "/dev/hidraw0"; echo "/dev/hidraw1"; }
    _fido2_device_desc() { echo "TestVendor"; }
    local out err
    out=$(_fido2_resolve_device <<<"2" 2>/tmp/fido2_test_err.$$)
    err=$(cat /tmp/fido2_test_err.$$); rm -f /tmp/fido2_test_err.$$
    assertEquals '/dev/hidraw1' "$out"
    assertContains 'menu wyboru musi wypisać obie ścieżki na stderr' "$err" '/dev/hidraw0'
    assertContains 'menu wyboru musi wypisać obie ścieżki na stderr' "$err" '/dev/hidraw1'
    unset -f _fido2_all_devices _fido2_device_desc
}

testResolveDeviceMultipleRetriesOnInvalidChoice() {
    _fido2_all_devices() { echo "/dev/hidraw0"; echo "/dev/hidraw1"; }
    _fido2_device_desc() { echo "TestVendor"; }
    local out
    out=$(_fido2_resolve_device 2>/dev/null <<<"9
1")
    assertEquals '/dev/hidraw0' "$out"
    unset -f _fido2_all_devices _fido2_device_desc
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
