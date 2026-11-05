#!/usr/bin/env bash
# Testy jednostkowe: services/nexus/key_setup.sh (prepare_key) - idempotencja i rotacja (#208).
# `openssl`, `sudo`, `chown` są atrapami w PATH (bez roota, bez prawdziwych kluczy).

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export MESSAGES_LANG=pl
export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/005_function_messages.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/020_function_process.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/services/nexus/key_setup.sh"

setUp() {
    _T="$(mktemp -d)"
    _ORIG_PATH="$PATH"
    mkdir -p "$_T/bin"
    export CALLS="$_T/calls.log"
    : >"$CALLS"
    cat >"$_T/bin/sudo" <<'S'
#!/usr/bin/env bash
[[ "$1" == "-K" ]] && exit 0
exec "$@"
S
    # openssl rand: każdy kolejny klucz inny (KEY-1, KEY-2, ...); OPENSSL_RAND_RC wymusza błąd
    cat >"$_T/bin/openssl" <<'S'
#!/usr/bin/env bash
[[ "${OPENSSL_RAND_RC:-0}" != 0 ]] && exit "$OPENSSL_RAND_RC"
n=$(cat "$CALLS.n" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$CALLS.n"
echo "KEY-$n"
S
    cat >"$_T/bin/chown" <<'S'
#!/usr/bin/env bash
echo "chown $*" >>"$CALLS"
S
    chmod +x "$_T/bin/sudo" "$_T/bin/openssl" "$_T/bin/chown"
    PATH="$_T/bin:$PATH"
    unset PREPARE_KEY_FORCE OPENSSL_RAND_RC
    export SERVICES_CONFIGURATION_DIR="$PROJECT_ROOT/services"
    export NEXUS_DATA="$_T/with space/nexus"
    _SECRET="$NEXUS_DATA/etc/keystore/nexus.secrets.json"
    mkdir -p "$(dirname "$_SECRET")"
    _SUDO_DEPTH=0
}

tearDown() {
    PATH="$_ORIG_PATH"
    rm -rf "$_T"
}

testMissingFileIsCreatedWithKeyAndPermissions() {
    out="$(prepare_key 2>&1)"
    assertEquals "rc" 0 $?
    assertTrue "plik powstał" "[ -s '$_SECRET' ]"
    assertContains "klucz wstawiony" "$(cat "$_SECRET")" '"key": "KEY-1"'
    assertNotContains "bez znacznika" "$(cat "$_SECRET")" '%%BASED_KEY%%'
    assertEquals "tryb 600" 600 "$(stat -c %a "$_SECRET")"
    assertContains "chown 200:200" "$(cat "$CALLS")" "chown 200:200 $_SECRET"
    assertNotContains "bez ostrzeżenia o rotacji" "$out" "Rotacja"
}

testExistingKeyIsKept() {
    prepare_key >/dev/null 2>&1
    before="$(cat "$_SECRET")"
    mtime_before="$(stat -c %Y "$_SECRET")"
    sleep 1
    out="$(prepare_key 2>&1)"
    assertEquals "rc" 0 $?
    assertEquals "zawartość bez zmian" "$before" "$(cat "$_SECRET")"
    assertEquals "mtime bez zmian" "$mtime_before" "$(stat -c %Y "$_SECRET")"
    assertContains "komunikat o pominięciu" "$out" "już istnieje"
    assertEquals "openssl rand wołany raz" 1 "$(cat "$CALLS.n")"
}

testSecondRunDoesNotCallOpensslOrChown() {
    prepare_key >/dev/null 2>&1
    : >"$CALLS"
    prepare_key >/dev/null 2>&1
    assertEquals "brak chown przy pominięciu" "" "$(cat "$CALLS")"
}

testForceFlagRotatesAndWarns() {
    prepare_key >/dev/null 2>&1
    out="$(prepare_key --force 2>&1)"
    assertEquals "rc" 0 $?
    assertContains "nowy klucz" "$(cat "$_SECRET")" '"key": "KEY-2"'
    assertContains "ostrzeżenie o utracie sekretów" "$out" "Rotacja klucza"
}

testForceEnvRotates() {
    prepare_key >/dev/null 2>&1
    PREPARE_KEY_FORCE=1 prepare_key >/dev/null 2>&1
    assertContains "nowy klucz" "$(cat "$_SECRET")" '"key": "KEY-2"'
}

testShortForceFlag() {
    prepare_key >/dev/null 2>&1
    prepare_key -f >/dev/null 2>&1
    assertContains "nowy klucz" "$(cat "$_SECRET")" '"key": "KEY-2"'
}

testForceWithoutExistingFileDoesNotWarn() {
    out="$(prepare_key --force 2>&1)"
    assertEquals "rc" 0 $?
    assertNotContains "bez ostrzeżenia" "$out" "Rotacja"
    assertContains "klucz" "$(cat "$_SECRET")" '"key": "KEY-1"'
}

testFileWithUnsubstitutedPlaceholderIsRegenerated() {
    printf '{"keys":[{"id":"home","key":"%%%%BASED_KEY%%%%"}]}' >"$_SECRET"
    prepare_key >/dev/null 2>&1
    assertContains "nowy klucz" "$(cat "$_SECRET")" '"key": "KEY-1"'
}

testFileWithEmptyKeyIsRegenerated() {
    printf '{"active":"home","keys":[{"id":"home","key":""}]}' >"$_SECRET"
    prepare_key >/dev/null 2>&1
    assertContains "nowy klucz" "$(cat "$_SECRET")" '"key": "KEY-1"'
}

testEmptyFileIsRegenerated() {
    : >"$_SECRET"
    prepare_key >/dev/null 2>&1
    assertContains "nowy klucz" "$(cat "$_SECRET")" '"key": "KEY-1"'
}

testMissingTemplateReturns1AndKeepsExistingFile() {
    prepare_key >/dev/null 2>&1
    before="$(cat "$_SECRET")"
    SERVICES_CONFIGURATION_DIR="$_T/nope" prepare_key >/dev/null 2>&1
    assertEquals "rc" 1 $?
    assertEquals "plik nietknięty" "$before" "$(cat "$_SECRET")"
}

testOpensslFailureReturns1AndKeepsFile() {
    printf '{"keys":[{"id":"home","key":""}]}' >"$_SECRET"
    OPENSSL_RAND_RC=1 prepare_key >/dev/null 2>&1
    assertEquals "rc" 1 $?
    assertContains "plik nietknięty" "$(cat "$_SECRET")" '"key":""'
}

testSudoSessionIsClosedOnEveryPath() {
    prepare_key >/dev/null 2>&1
    assertEquals "po utworzeniu" 0 "${_SUDO_DEPTH:-0}"
    prepare_key >/dev/null 2>&1
    assertEquals "po pominięciu" 0 "${_SUDO_DEPTH:-0}"
    OPENSSL_RAND_RC=1 prepare_key --force >/dev/null 2>&1
    assertEquals "po błędzie openssl" 0 "${_SUDO_DEPTH:-0}"
}

testSecretNeverInArgv() {
    # sekret idzie przez stdin tee, nie przez argumenty procesu (sed -i itp.) - pomijamy komentarze
    grep -v '^[[:space:]]*#' "$PROJECT_ROOT/services/nexus/key_setup.sh" | grep -qE '\bsed\b'
    assertNotEquals "brak sed w kodzie" 0 $?
}

testFunctionIsExportedToChildProcesses() {
    out="$(bash -c ". '$PROJECT_ROOT/services/nexus/key_setup.sh'; bash -c 'declare -F prepare_key'")"
    assertEquals "prepare_key" "prepare_key" "$out"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
