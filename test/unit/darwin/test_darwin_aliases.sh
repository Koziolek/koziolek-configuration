#!/usr/bin/env bash
# macOS-specific: aliasy ustawiane gdy OS_TYPE=Darwin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

_ALIASES=''

oneTimeSetUp() {
    _ALIASES="$(bash --norc --noprofile -c "
        export OS_TYPE='Darwin'
        shopt -s expand_aliases
        . '$PROJECT_ROOT/bash/bash_aliases.sh' 2>/dev/null
        alias
    " 2>/dev/null)"
}

testInWindowIsOpenOnDarwin() {
    assertContains 'in-window musi być open na Darwin' \
        "$_ALIASES" "'open'"
}

testInWindowIsNotXdgOpenOnDarwin() {
    assertNotContains 'in-window nie może być xdg-open na Darwin' \
        "$_ALIASES" 'xdg-open'
}

testNoFixNetOnDarwin() {
    assertNotContains 'fix-net nie może istnieć na Darwin' \
        "$_ALIASES" 'fix-net'
}

testNoIotopOnDarwin() {
    assertNotContains 'iotop nie może istnieć na Darwin' \
        "$_ALIASES" 'alias iotop'
}

testNoFlatpakOnDarwin() {
    assertNotContains 'cozy/flatpak nie może istnieć na Darwin' \
        "$_ALIASES" 'flatpak'
}

testLsUsesColorFlagGOnDarwin() {
    assertContains 'ls musi używać -G na Darwin' \
        "$_ALIASES" 'ls -G'
}

testAlertUsesOsascriptOnDarwin() {
    assertContains 'alert musi używać osascript na Darwin' \
        "$_ALIASES" 'osascript'
}

testAlertDoesNotUseNotifySendOnDarwin() {
    assertNotContains 'alert nie może używać notify-send na Darwin' \
        "$_ALIASES" 'notify-send'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
