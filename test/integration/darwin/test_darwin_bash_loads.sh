#!/usr/bin/env bash
# macOS integration: bash/main.sh ładuje się poprawnie gdy OS_TYPE=Darwin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

_FAKE_HOME=''
_OUT=''

oneTimeSetUp() {
    _FAKE_HOME="$(mktemp -d)"
    _OUT="$_FAKE_HOME/load.out"

    local tools="$_FAKE_HOME/workspace/tools"
    mkdir -p \
        "$tools/shunit2" "$tools/BashMan" \
        "$tools/FossFLOW" "$tools/maven-bash-completion"
    touch "$tools/shunit2/shunit2.sh" "$tools/BashMan/bashman.sh"
    touch "$_FAKE_HOME/.senv"
    chmod 400 "$_FAKE_HOME/.senv"

    # OS_TYPE=Darwin ustawiony z zewnątrz (jak robi to root main.sh po uname)
    bash -c "
        export HOME='$_FAKE_HOME'
        export OS_TYPE='Darwin'
        export BASH_CONFIGURATION_DIR='$PROJECT_ROOT/bash'
        export GIT_CONFIGURATION_DIR='$PROJECT_ROOT/git'
        export SERVICES_CONFIGURATION_DIR='$PROJECT_ROOT/services'
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

        . '$PROJECT_ROOT/bash/main.sh' 2>/dev/null
        echo \"EXIT:\$?\"
        echo \"OS_TYPE:\$OS_TYPE\"
        [[ \"\$OS_TYPE\" == 'Darwin' ]] && echo 'IS_DARWIN=ok'
        [[ -n \"\${BASH_FUNCTIONS_LOADED:-}\" ]] && echo 'BASH_LOADED=ok'
        declare -f log_info  >/dev/null 2>&1 && echo 'FUNC_LOG=ok'
        declare -f get_and_build >/dev/null 2>&1 && echo 'FUNC_GAB=ok'
    " > "$_OUT" 2>/dev/null
}

oneTimeTearDown() {
    rm -rf "$_FAKE_HOME"
}

_out() { cat "$_OUT"; }

testBashLoadsOnDarwin() {
    assertContains 'bash/main.sh musi załadować się z kodem 0 na Darwin' \
        "$(_out)" 'EXIT:0'
}

testOsTypePreservedAsDarwin() {
    assertContains 'OS_TYPE musi pozostać Darwin po załadowaniu bash/main.sh' \
        "$(_out)" 'OS_TYPE:Darwin'
}

testIsDarwinFlagSet() {
    assertContains 'IS_DARWIN musi być ustawiony' "$(_out)" 'IS_DARWIN=ok'
}

testBashFunctionsLoadedOnDarwin() {
    assertContains 'BASH_FUNCTIONS_LOADED musi być ustawiony na Darwin' \
        "$(_out)" 'BASH_LOADED=ok'
}

testLogFunctionsAvailableOnDarwin() {
    assertContains 'log_info musi być dostępna po załadowaniu na Darwin' \
        "$(_out)" 'FUNC_LOG=ok'
}

testGetAndBuildAvailableOnDarwin() {
    assertContains 'get_and_build musi być dostępna po załadowaniu na Darwin' \
        "$(_out)" 'FUNC_GAB=ok'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
