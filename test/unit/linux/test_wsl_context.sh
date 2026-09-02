#!/usr/bin/env bash
# Kontekst wsl: łańcuch "linux debian wsl" (WSL jest w praktyce zawsze Ubuntu/Debian
# pod spodem, więc dziedziczy apt-fallback instalacji hub z debian.sh). Override
# in-window na mostek Windows, reszta (cozy/iotop/fd/alert/...) z contexts/linux.sh.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# $1 = mocki narzędzi (np. definicja wslview); wypisuje `alias`
_wsl_aliases() {
    env -u WAYLAND_DISPLAY -u DISPLAY bash --norc --noprofile -c "
        export OS_TYPE='Linux' CONFIG_CONTEXT_FORCE='wsl' CONFIG_CONTEXT='wsl'
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        shopt -s expand_aliases
        hub() { :; }; export -f hub
        $1
        . '$PROJECT_ROOT/bash/contexts/detect.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/bash_aliases.sh' 2>/dev/null
        for c in \$(context_chain); do
            . \"$PROJECT_ROOT/bash/contexts/\$c.sh\" 2>/dev/null || true
        done
        alias
    " 2>/dev/null
}

testChainIsLinuxDebianWsl() {
    . "$PROJECT_ROOT/bash/contexts/detect.sh"
    assertEquals 'linux debian wsl' "$(context_chain wsl | tr '\n' ' ' | sed 's/ $//')"
}

testInWindowUsesWslviewWhenPresent() {
    local out
    out="$(_wsl_aliases 'wslview() { :; }; export -f wslview')"
    assertContains 'in-window musi wskazywać wslview' "$out" "in-window='wslview'"
}

testInWindowFallsBackToExplorer() {
    local out
    out="$(_wsl_aliases 'explorer.exe() { :; }; export -f explorer.exe')"
    assertContains 'bez wslview -> explorer.exe' "$out" "in-window='explorer.exe'"
}

testInheritsLinuxAliases() {
    local out
    out="$(_wsl_aliases '')"
    assertContains 'wsl dziedziczy aliasy linux (cozy)' "$out" 'cozy'
    assertContains 'wsl dziedziczy aliasy linux (iotop)' "$out" 'iotop'
}

testNoFixNetOnWsl() {
    local out
    out="$(_wsl_aliases '')"
    assertNotContains 'fix-net jest tylko dla vanilla' "$out" 'fix-net'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
