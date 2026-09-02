#!/usr/bin/env bash
# Kontekst debian: instalacja `hub` przez apt (przeniesiona z bash_aliases.sh).
# debian jest wspólny dla łańcuchów ubuntu i vanilla.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

_DEBIAN="$PROJECT_ROOT/bash/contexts/debian.sh"

# $1 = 'present' | 'absent' (czy hub jest); wypisuje wywołania apt-get + alias
_run_debian_ctx() {
    local hub_state="$1" bin calls
    bin="$(mktemp -d)"
    calls="$bin/calls"
    printf '#!/bin/sh\necho "apt-get $*" >> "%s"\nexit 0\n' "$calls" > "$bin/apt-get"
    printf '#!/bin/sh\nexec "$@"\n' > "$bin/sudo"
    chmod +x "$bin/apt-get" "$bin/sudo"

    PATH="$bin:$PATH" bash --norc --noprofile -c "
        shopt -s expand_aliases
        command() {
            if [ \"\$1\" = -v ] && [ \"\$2\" = hub ]; then
                [ '$hub_state' = present ] && return 0 || return 1
            fi
            builtin command \"\$@\"
        }
        make_me_sudo() { SUDO='sudo'; }
        unmake_me_sudo() { :; }
        log_warn() { echo \"warn: \$*\"; }
        . '$_DEBIAN' 2>&1
        alias git 2>/dev/null || echo 'NO-GIT-ALIAS'
    "
    cat "$calls" 2>/dev/null
    rm -rf "$bin"
}

testInstallsHubViaAptWhenAbsent() {
    local out
    out="$(_run_debian_ctx absent)"
    assertContains 'debian.sh musi wołać apt-get install hub' "$out" 'apt-get install -qqy hub'
}

testSetsGitAliasAfterInstall() {
    local out
    out="$(_run_debian_ctx absent)"
    assertContains 'po instalacji ma być alias git=hub' "$out" "alias git='hub'"
}

testSkipsAptWhenHubPresent() {
    local out
    out="$(_run_debian_ctx present)"
    assertNotContains 'z hub obecnym nie ruszamy apt' "$out" 'apt-get'
}

testChainVanillaIncludesDebian() {
    # sanity: łańcuch vanilla przechodzi przez debian, więc dziedziczy ten plik
    . "$PROJECT_ROOT/bash/contexts/detect.sh"
    assertEquals 'linux debian vanilla' \
        "$(context_chain vanilla | tr '\n' ' ' | sed 's/ $//')"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
