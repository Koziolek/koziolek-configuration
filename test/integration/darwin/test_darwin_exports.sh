#!/usr/bin/env bash
# macOS integration: bash_exports.sh z OS_TYPE=Darwin dodaje Homebrew PATH

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"

_FAKE_HOME=''
_FAKE_BREW=''

oneTimeSetUp() {
    _FAKE_HOME="$(mktemp -d)"
    _FAKE_BREW="$_FAKE_HOME/fake_homebrew"
    mkdir -p "$_FAKE_BREW/bin" "$_FAKE_BREW/sbin"
    touch "$_FAKE_HOME/.senv"
    chmod 400 "$_FAKE_HOME/.senv"
}

oneTimeTearDown() {
    rm -rf "$_FAKE_HOME"
}

_get_darwin_export() {
    local varname="$1"
    local brew_prefix="${2:-}"
    local extra="${3:-}"
    HOME="$_FAKE_HOME" bash --norc --noprofile -c "
        export OS_TYPE='Darwin'
        uname() { echo 'Darwin'; }
        export -f uname
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        docker() { return 0; }; export -f docker
        $extra
        { . '$PROJECT_ROOT/bash/bash_exports.sh'; } >/dev/null 2>&1
        printf '%s' \"\${$varname:-}\"
    "
}

# Homebrew żyje teraz w bash/contexts/darwin.sh (nie w bash_exports.sh).
# darwin.sh honoruje wstrzyknięty $HOMEBREW_PREFIX gdy /opt/homebrew nie istnieje.
_load_darwin_ctx() {
    # $1 = kod do wypisania wyniku; $2 = preambuła
    HOME="$_FAKE_HOME" bash --norc --noprofile -c "
        export OS_TYPE='Darwin' ASDF_DATA_DIR='$_FAKE_HOME/.asdf'
        export PATH='/usr/bin:/bin'
        ${2:-}
        { . '$PROJECT_ROOT/bash/contexts/darwin.sh'; } >/dev/null 2>&1
        $1
    "
}

testHomebrewPrefixHonoredByDarwinContext() {
    local result
    result="$(_load_darwin_ctx "printf '%s' \"\${HOMEBREW_PREFIX:-}\"" \
        "export HOMEBREW_PREFIX='$_FAKE_BREW'; mkdir -p '$_FAKE_BREW/bin' '$_FAKE_BREW/sbin'")"
    assertEquals 'darwin.sh musi respektować wstrzyknięty HOMEBREW_PREFIX' \
        "$_FAKE_BREW" "$result"
}

testPathGetsHomebrewBinFromDarwinContext() {
    local result
    result="$(_load_darwin_ctx "printf '%s' \"\$PATH\"" \
        "export HOMEBREW_PREFIX='$_FAKE_BREW'; mkdir -p '$_FAKE_BREW/bin' '$_FAKE_BREW/sbin'")"
    assertContains 'PATH musi zawierać homebrew bin po darwin.sh' "$result" "$_FAKE_BREW/bin"
}

testLocalBinKeepsPriorityOverHomebrew() {
    local result
    result="$(_load_darwin_ctx "printf '%s' \"\$PATH\"" \
        "export HOMEBREW_PREFIX='$_FAKE_BREW'; mkdir -p '$_FAKE_BREW/bin' '$_FAKE_BREW/sbin'")"
    assertTrue '.local/bin musi być przed homebrew w PATH' \
        "[[ '$result' == '$_FAKE_HOME/.local/bin:'* ]]"
}

testDarwinContextSetsDockerCompose() {
    local result
    result="$(_load_darwin_ctx "printf '%s' \"\${DOCKER_COMPOSE:-}\"" \
        'docker() { return 0; }; export -f docker')"
    assertEquals 'darwin.sh musi ustawić DOCKER_COMPOSE na "docker compose"' \
        'docker compose' "$result"
}

testExportsLoadWithoutErrorOnDarwin() {
    local rc
    HOME="$_FAKE_HOME" bash --norc --noprofile -c "
        export OS_TYPE='Darwin'
        uname() { echo 'Darwin'; }
        export -f uname
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        docker() { return 0; }; export -f docker
        . '$PROJECT_ROOT/bash/bash_exports.sh' >/dev/null 2>&1
    "
    rc=$?
    assertEquals 'bash_exports.sh musi ładować się bez błędu na Darwin' 0 $rc
}

testSdkmanDirSetOnDarwin() {
    local result
    result="$(_get_darwin_export 'SDKMAN_DIR')"
    assertNotNull 'SDKMAN_DIR musi być ustawiony na Darwin' "$result"
}

testWorkspaceSetOnDarwin() {
    local result
    result="$(_get_darwin_export 'WORKSPACE')"
    assertNotNull 'WORKSPACE musi być ustawiony na Darwin' "$result"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
