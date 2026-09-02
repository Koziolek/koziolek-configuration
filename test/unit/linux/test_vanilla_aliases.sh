#!/usr/bin/env bash
# Vanilla OS: łańcuch kontekstów "linux debian vanilla".
# fix-net jest swoiste dla vanilla (przeniesione z bash_aliases.sh, gdzie było
# BŁĘDNIE aliasem dla całego "nie-Darwin").

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

_ALIASES=''

oneTimeSetUp() {
    _ALIASES="$(bash --norc --noprofile -c "
        export OS_TYPE='Linux' CONFIG_CONTEXT_FORCE='vanilla' CONFIG_CONTEXT='vanilla'
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

testFixNetExistsOnVanilla() {
    assertContains 'fix-net musi istnieć w kontekście vanilla' "$_ALIASES" 'fix-net'
}

testFixNetUsesRunHostResolvConf() {
    assertContains 'fix-net musi montować /run/host/etc/resolv.conf' \
        "$_ALIASES" '/run/host/etc/resolv.conf'
}

testVanillaStillGetsLinuxAliases() {
    # łańcuch zawiera "linux" => wspólne aliasy Linuksa nadal obowiązują
    assertContains 'in-window musi być xdg-open (z contexts/linux.sh)' "$_ALIASES" 'xdg-open'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
