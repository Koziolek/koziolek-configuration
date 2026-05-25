#!/usr/bin/env bash
# Testy integracyjne: aliasy git (git/aliases)
# Odczytuje aliasy bezpośrednio z pliku git/aliases przez "git config --file".

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"

_ALIASES_FILE="$PROJECT_ROOT/git/aliases"

# Pomocnik: odczytuje wartość aliasu z pliku git/aliases
_alias() { git config --file "$_ALIASES_FILE" "alias.$1" 2>/dev/null || true; }

# ---------------------------------------------------------------------------

testAliasFunDefined() {
    assertNotNull 'alias fun musi być zdefiniowany' "$(_alias fun)"
}

testAliasStEqualsStatus() {
    assertEquals 'alias st musi być "status"' 'status' "$(_alias st)"
}

testAliasCiEqualsCommit() {
    assertEquals 'alias ci musi być "commit"' 'commit' "$(_alias ci)"
}

testAliasFuckIsResetSoftHead() {
    assertEquals 'alias fuck musi być "reset --soft HEAD~"' \
        'reset --soft HEAD~' "$(_alias fuck)"
}

testAliasNbCallsNewFeatureBranch() {
    assertContains 'alias nb musi odwoływać się do git_new_feature_branch' \
        "$(_alias nb)" 'git_new_feature_branch'
}

testAliasLaListsAliases() {
    assertContains 'alias la musi listować aliasy przez git config' \
        "$(_alias la)" 'alias'
}

testAliasPushUpstreamDefined() {
    assertNotNull 'alias push-upstream musi być zdefiniowany' "$(_alias push-upstream)"
}

testAliasLgDefined() {
    assertEquals 'alias lg musi być "log -p"' 'log -p' "$(_alias lg)"
}

testAliasesFileContainsAliasSection() {
    assertContains 'git/aliases musi zawierać sekcję [alias]' \
        "$(cat "$_ALIASES_FILE")" '[alias]'
}

testGitConfigTemplateIncludesAliasesFile() {
    assertContains 'git_config musi dołączać plik aliases przez [include]' \
        "$(cat "$PROJECT_ROOT/git/git_config")" 'aliases'
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
