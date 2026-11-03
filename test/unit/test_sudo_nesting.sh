#!/usr/bin/env bash
# Testy jednostkowe: make_me_sudo / unmake_me_sudo (bash/functions.d/020_function_process.sh)
# Zakres: zagnieżdżanie (jedno `sudo -K` na najbardziej zewnętrzną parę), zachowanie pojedynczej pary,
#         brak wycieku SUDO/RESET_SUDO. Atrapa `sudo` w PATH liczy wywołania.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/020_function_process.sh"

_TEST_DIR=''
_ORIG_PATH=''

setUp() {
    _TEST_DIR="$(mktemp -d)"
    _ORIG_PATH="$PATH"
    SUDO_LOG="$_TEST_DIR/sudo.log"
    export SUDO_LOG
    : >"$SUDO_LOG"
    mkdir -p "$_TEST_DIR/bin"
    cat >"$_TEST_DIR/bin/sudo" <<'EOS'
#!/usr/bin/env bash
echo "sudo $*" >> "$SUDO_LOG"
EOS
    chmod +x "$_TEST_DIR/bin/sudo"
    export PATH="$_TEST_DIR/bin:$PATH"
    unset SUDO RESET_SUDO _SUDO_DEPTH
}

tearDown() {
    export PATH="$_ORIG_PATH"
    rm -rf "$_TEST_DIR"
}

_revocations() {
    grep -c -- 'sudo -K' "$SUDO_LOG"
}

testSinglePairRevokesOnce() {
    [ "$(id -u)" -eq 0 ] && startSkipping
    make_me_sudo
    assertEquals sudo "$SUDO"
    unmake_me_sudo
    assertEquals 1 "$(_revocations)"
    assertNull "SUDO nie wycieka" "${SUDO:-}"
    assertNull "RESET_SUDO nie wycieka" "${RESET_SUDO:-}"
}

testNestedPairsRevokeOnlyAtOutermostEnd() {
    [ "$(id -u)" -eq 0 ] && startSkipping
    make_me_sudo
    make_me_sudo
    make_me_sudo
    unmake_me_sudo
    unmake_me_sudo
    assertEquals "bez odwołania przed zamknięciem zewnętrznej pary" 0 "$(_revocations)"
    assertEquals "SUDO zostaje w trakcie sesji" sudo "$SUDO"
    unmake_me_sudo
    assertEquals 1 "$(_revocations)"
    assertNull "${SUDO:-}"
}

testSequentialPairsEachRevoke() {
    [ "$(id -u)" -eq 0 ] && startSkipping
    make_me_sudo
    unmake_me_sudo
    make_me_sudo
    unmake_me_sudo
    assertEquals 2 "$(_revocations)"
}

testUnmatchedUnmakeBehavesAsBefore() {
    [ "$(id -u)" -eq 0 ] && startSkipping
    export SUDO=sudo RESET_SUDO=1
    unmake_me_sudo
    assertEquals 1 "$(_revocations)"
    assertNull "${SUDO:-}"
}

testRootNeverCallsSudo() {
    [ "$(id -u)" -ne 0 ] && startSkipping
    make_me_sudo
    make_me_sudo
    assertEquals '' "$SUDO"
    unmake_me_sudo
    unmake_me_sudo
    assertEquals 0 "$(_revocations)"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
