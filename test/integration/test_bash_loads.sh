#!/usr/bin/env bash
# Testy integracyjne: ładowanie bash/main.sh w kontenerze bez X11.
# Sourcuje pełny stos konfiguracji w izolowanym subshell i sprawdza wyniki.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

_FAKE_HOME=''
_OUT=''

oneTimeSetUp() {
    _FAKE_HOME="$(mktemp -d)"
    _OUT="$_FAKE_HOME/load.out"

    # Pre-tworzenie katalogów narzędzi — install_lib trafia w fast-path, brak git clone
    local tools="$_FAKE_HOME/workspace/tools"
    mkdir -p \
        "$tools/shunit2" \
        "$tools/BashMan" \
        "$tools/FossFLOW" \
        "$tools/maven-bash-completion"
    touch "$tools/shunit2/shunit2.sh"
    touch "$tools/BashMan/bashman.sh"

    # .senv wymagany przez bash_exports.sh
    touch "$_FAKE_HOME/.senv"
    chmod 400 "$_FAKE_HOME/.senv"

    # Sourcujemy bash/main.sh w czystym subshell; wyniki trafiają do pliku
    bash -c "
        export HOME='$_FAKE_HOME'
        export BASH_CONFIGURATION_DIR='$PROJECT_ROOT/bash'
        export GIT_CONFIGURATION_DIR='$PROJECT_ROOT/git'
        export SERVICES_CONFIGURATION_DIR='$PROJECT_ROOT/services'
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

        . '$PROJECT_ROOT/bash/main.sh' 2>/dev/null
        echo \"EXIT:\$?\"

        declare -f log_info      >/dev/null 2>&1 && echo 'FUNC_LOG_INFO=ok'
        declare -f get_and_build >/dev/null 2>&1 && echo 'FUNC_GAB=ok'
        declare -f install_lib   >/dev/null 2>&1 && echo 'FUNC_INSTALL_LIB=ok'
        declare -f source_directory >/dev/null 2>&1 && echo 'FUNC_SOURCE_DIR=ok'

        [[ \"\$PROMPT_COMMAND\" == *_sdkman_init* ]] && echo 'PROMPT_CMD_SDKMAN=ok'
        [[ -n \"\$WORKSPACE\" ]] && echo 'VAR_WORKSPACE=ok'
        [[ -n \"\$WORKSPACE_TOOLS\" ]] && echo 'VAR_WORKSPACE_TOOLS=ok'
    " > "$_OUT" 2>/dev/null
}

oneTimeTearDown() {
    rm -rf "$_FAKE_HOME"
}

_out() { cat "$_OUT"; }

# ---------------------------------------------------------------------------

testBashMainExitsZero() {
    assertContains 'bash/main.sh musi załadować się z kodem 0' \
        "$(_out)" 'EXIT:0'
}

testLogFunctionsAvailableAfterLoad() {
    assertContains 'log_info musi być dostępna po załadowaniu' \
        "$(_out)" 'FUNC_LOG_INFO=ok'
}

testGetAndBuildAvailableAfterLoad() {
    assertContains 'get_and_build musi być dostępna po załadowaniu' \
        "$(_out)" 'FUNC_GAB=ok'
}

testInstallLibAvailableAfterLoad() {
    assertContains 'install_lib musi być dostępna po załadowaniu' \
        "$(_out)" 'FUNC_INSTALL_LIB=ok'
}

testSourceDirectoryAvailableAfterLoad() {
    assertContains 'source_directory musi być dostępna po załadowaniu' \
        "$(_out)" 'FUNC_SOURCE_DIR=ok'
}

testPromptCommandContainsSdkmanInit() {
    assertContains 'PROMPT_COMMAND musi zawierać _sdkman_init po załadowaniu' \
        "$(_out)" 'PROMPT_CMD_SDKMAN=ok'
}

testWorkspaceExportedAfterLoad() {
    assertContains 'WORKSPACE musi być ustawiony po załadowaniu' \
        "$(_out)" 'VAR_WORKSPACE=ok'
}

testWorkspaceToolsExportedAfterLoad() {
    assertContains 'WORKSPACE_TOOLS musi być ustawiony po załadowaniu' \
        "$(_out)" 'VAR_WORKSPACE_TOOLS=ok'
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
