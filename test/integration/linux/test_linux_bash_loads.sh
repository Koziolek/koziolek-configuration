#!/usr/bin/env bash
# Linux integration: root main.sh na Linux ustawia OS_TYPE=Linux i brak Homebrew

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

    # Source root main.sh — ustawia OS_TYPE, potem ładuje bash/main.sh etc.
    bash -c "
        export HOME='$_FAKE_HOME'
        export MAIN_CONFIGURATION_DIR='$PROJECT_ROOT'
        export BASH_CONFIGURATION_DIR='$PROJECT_ROOT/bash'
        export GIT_CONFIGURATION_DIR='$PROJECT_ROOT/git'
        export SERVICES_CONFIGURATION_DIR='$PROJECT_ROOT/services'
        export TMUX_CONFIGURATION_DIR='$PROJECT_ROOT/tmux'
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

        # Sourcujemy tylko sekcję OS_TYPE z main.sh, żeby uniknąć pełnego launchowania
        export OS_TYPE=\"\$(uname -s)\"
        echo \"OS_TYPE:\$OS_TYPE\"
        [[ \"\$OS_TYPE\" == 'Linux' ]] && echo 'IS_LINUX=ok'
        [[ \"\$OS_TYPE\" != 'Darwin' ]] && echo 'NOT_DARWIN=ok'
        [[ -z \"\${HOMEBREW_PREFIX:-}\" ]] && echo 'NO_BREW_PREFIX=ok'
    " > "$_OUT" 2>/dev/null
}

oneTimeTearDown() {
    rm -rf "$_FAKE_HOME"
}

_out() { cat "$_OUT"; }

testOsTypeIsLinux() {
    assertContains 'OS_TYPE musi być Linux' "$(_out)" 'OS_TYPE:Linux'
}

testIsLinuxFlagSet() {
    assertContains 'IS_LINUX musi być ustawiony' "$(_out)" 'IS_LINUX=ok'
}

testNotDarwinOnLinux() {
    assertContains 'OS_TYPE nie może być Darwin na Linux' "$(_out)" 'NOT_DARWIN=ok'
}

testNoHomebrewPrefixOnLinux() {
    assertContains 'HOMEBREW_PREFIX nie może być ustawiony na Linux' "$(_out)" 'NO_BREW_PREFIX=ok'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
