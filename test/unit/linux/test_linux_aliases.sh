#!/usr/bin/env bash
# Linux-specific: aliasy ustawiane gdy OS_TYPE=Linux

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

_ALIASES=''

oneTimeSetUp() {
    _ALIASES="$(bash --norc --noprofile -c "
        export OS_TYPE='Linux'
        shopt -s expand_aliases
        . '$PROJECT_ROOT/bash/bash_aliases.sh' 2>/dev/null
        alias
    " 2>/dev/null)"
}

testInWindowIsXdgOpenOnLinux() {
    assertContains 'in-window musi być xdg-open na Linux' \
        "$_ALIASES" 'xdg-open'
}

testFixNetExistsOnLinux() {
    assertContains 'fix-net musi istnieć na Linux' \
        "$_ALIASES" 'fix-net'
}

testIotopExistsOnLinux() {
    assertContains 'iotop musi istnieć na Linux' \
        "$_ALIASES" 'iotop'
}

testCozzyExistsOnLinux() {
    assertContains 'cozy musi istnieć na Linux (flatpak)' \
        "$_ALIASES" 'cozy'
}

testLsUsesColorAutoOnLinux() {
    # dircolors może nie być dostępny w Alpine — test sprawdza brak -G (macOS flagi)
    assertNotContains 'ls nie może używać -G na Linux' \
        "$_ALIASES" "ls -G"
}

testFdAliasForFdfindOnLinux() {
    # Jeśli fdfind istnieje → fd powinno być aliasem
    if command -v fdfind >/dev/null 2>&1; then
        assertContains 'fd musi być aliasem fdfind gdy fdfind dostępny' \
            "$_ALIASES" 'fdfind'
    else
        echo "fdfind niedostępny — pomijam test aliasu fd"
    fi
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
