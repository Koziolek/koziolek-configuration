#!/usr/bin/env bash
# Linux-specific: aliasy z bash_aliases.sh + bash/contexts/{linux,debian}.sh
# (kontekst debian => łańcuch "linux debian", bez vanilla)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

_ALIASES=''

oneTimeSetUp() {
    _ALIASES="$(bash --norc --noprofile -c "
        export OS_TYPE='Linux' CONFIG_CONTEXT_FORCE='debian' CONFIG_CONTEXT='debian'
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        shopt -s expand_aliases
        hub() { :; }; export -f hub   # udawaj, że hub jest — pomiń instalację per-kontekst
        . '$PROJECT_ROOT/bash/contexts/detect.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/bash_aliases.sh' 2>/dev/null
        for c in \$(context_chain); do
            . \"$PROJECT_ROOT/bash/contexts/\$c.sh\" 2>/dev/null || true
        done
        alias
    " 2>/dev/null)"
}

testInWindowIsXdgOpenOnLinux() {
    assertContains 'in-window musi być xdg-open na Linux' "$_ALIASES" 'xdg-open'
}

testNoFixNetOnPlainLinux() {
    # fix-net jest teraz swoiste dla vanilla, nie dla całego Linuksa
    assertNotContains 'fix-net nie może istnieć w kontekście debian' "$_ALIASES" 'fix-net'
}

testIotopExistsOnLinux() {
    assertContains 'iotop musi istnieć na Linux' "$_ALIASES" 'iotop'
}

testCozzyExistsOnLinux() {
    assertContains 'cozy musi istnieć na Linux (flatpak)' "$_ALIASES" 'cozy'
}

testLsUsesColorAutoOnLinux() {
    assertNotContains 'ls nie może używać -G na Linux' "$_ALIASES" "ls -G"
}

testFdAliasForFdfindOnLinux() {
    if command -v fdfind >/dev/null 2>&1; then
        assertContains 'fd musi być aliasem fdfind gdy fdfind dostępny' "$_ALIASES" 'fdfind'
    else
        echo "fdfind niedostępny — pomijam test aliasu fd"
    fi
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
