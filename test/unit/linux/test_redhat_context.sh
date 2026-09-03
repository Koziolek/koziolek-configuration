#!/usr/bin/env bash
# Kontekst redhat: instalacja `hub` przez yum (mirror test_debian_context.sh).

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

_REDHAT="$PROJECT_ROOT/bash/contexts/redhat.sh"

# $1 = 'present' | 'absent' (czy hub jest); wypisuje wywołania yum + alias
_run_redhat_ctx() {
    local hub_state="$1" bin calls
    bin="$(mktemp -d)"
    calls="$bin/calls"
    printf '#!/bin/sh\necho "yum $*" >> "%s"\nexit 0\n' "$calls" > "$bin/yum"
    printf '#!/bin/sh\nexec "$@"\n' > "$bin/sudo"
    chmod +x "$bin/yum" "$bin/sudo"

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
        . '$_REDHAT' 2>&1
        alias git 2>/dev/null || echo 'NO-GIT-ALIAS'
    "
    cat "$calls" 2>/dev/null
    rm -rf "$bin"
}

testInstallsHubViaYumWhenAbsent() {
    local out
    out="$(_run_redhat_ctx absent)"
    assertContains 'redhat.sh musi wołać yum install hub' "$out" 'yum install -y hub'
}

testSetsGitAliasAfterInstall() {
    local out
    out="$(_run_redhat_ctx absent)"
    assertContains 'po instalacji ma być alias git=hub' "$out" "alias git='hub'"
}

testSkipsYumWhenHubPresent() {
    local out
    out="$(_run_redhat_ctx present)"
    assertNotContains 'z hub obecnym nie ruszamy yum' "$out" 'yum'
}

testChainRedhatIsLinuxRedhat() {
    . "$PROJECT_ROOT/bash/contexts/detect.sh"
    assertEquals 'linux redhat' \
        "$(context_chain redhat | tr '\n' ' ' | sed 's/ $//')"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
