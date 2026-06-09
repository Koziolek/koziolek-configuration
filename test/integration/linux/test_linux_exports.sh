#!/usr/bin/env bash
# Linux integration: bash_exports.sh na Linux nie dodaje Homebrew PATH

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"

_FAKE_HOME=''

oneTimeSetUp() {
    _FAKE_HOME="$(mktemp -d)"
    touch "$_FAKE_HOME/.senv"
    chmod 400 "$_FAKE_HOME/.senv"
}

oneTimeTearDown() {
    rm -rf "$_FAKE_HOME"
}

_get_export() {
    local varname="$1"
    local preamble="${2:-}"
    HOME="$_FAKE_HOME" bash -c "
        export OS_TYPE='Linux'
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        $preamble
        { . '$PROJECT_ROOT/bash/bash_exports.sh'; } >/dev/null 2>&1
        printf '%s' \"\${$varname:-}\"
    "
}

_WITH_DOCKER='docker() { return 0; }; export -f docker'

testNoHomebrewPrefixOnLinux() {
    local result
    result="$(_get_export 'HOMEBREW_PREFIX' "$_WITH_DOCKER")"
    assertEquals 'HOMEBREW_PREFIX musi być pusty na Linux' '' "$result"
}

testPathDoesNotContainHomebrewOnLinux() {
    local result
    result="$(HOME="$_FAKE_HOME" bash -c "
        export OS_TYPE='Linux'
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        $_WITH_DOCKER
        { . '$PROJECT_ROOT/bash/bash_exports.sh'; } >/dev/null 2>&1
        printf '%s' \"\$PATH\"
    ")"
    assertNotContains 'PATH nie może zawierać homebrew na Linux' "$result" 'homebrew'
}

testSenvPermissionsAreUserReadOnlyOnLinux() {
    rm -f "$_FAKE_HOME/.senv"
    HOME="$_FAKE_HOME" bash -c "
        export OS_TYPE='Linux'
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        $_WITH_DOCKER
        { . '$PROJECT_ROOT/bash/bash_exports.sh'; } >/dev/null 2>&1
    "
    local perms
    perms="$(stat -c '%a' "$_FAKE_HOME/.senv" 2>/dev/null || echo 'missing')"
    assertEquals '.senv musi mieć uprawnienia 400' '400' "$perms"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
