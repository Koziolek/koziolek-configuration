#!/usr/bin/env bash
# Testy integracyjne: bash_completion.sh
# complete działa w nieinteaktywnym bash — nie potrzeba bash -i.
# Każdy test sourcuje plik w izolowanym subshell (bash -c) z zamockowanymi zależnościami.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"

_FAKE_HOME=''

oneTimeSetUp() {
    _FAKE_HOME="$(mktemp -d)"
    mkdir -p "$_FAKE_HOME/.cache" "$_FAKE_HOME/.local/bin"
}

oneTimeTearDown() {
    rm -rf "$_FAKE_HOME"
}

setUp() {
    rm -f "$_FAKE_HOME/.cache/asdf_bash_completion"
}

# Sourcuje bash_completion.sh w subshell z mockami sdk i asdf.
# Wypisuje wynik complete -p oraz ewentualne znaczniki na stdout.
_source_and_check() {
    local extra_setup="${1:-}"
    local extra_check="${2:-}"
    bash -c "
        sdk()  { return 0; }; export -f sdk
        $extra_setup
        export HOME='$_FAKE_HOME'
        . '$PROJECT_ROOT/bash/bash_completion.sh' 2>/dev/null
        $extra_check
        complete -p 2>/dev/null
    "
}

# ---------------------------------------------------------------------------

testLazyCompletionRegistered() {
    local output
    output="$(_source_and_check)"
    assertContains 'complete -D musi rejestrować _lazy_completion' \
        "$output" '_lazy_completion'
}

testGitLazyCompletionRegisteredForG() {
    local output
    output="$(_source_and_check)"
    # complete -p g musi zawierać -F _git_lazy
    local g_spec
    g_spec="$(echo "$output" | grep ' g$')"
    assertContains 'complete dla "g" musi wskazywać na _git_lazy' \
        "$g_spec" '_git_lazy'
}

testGitLazyCompletionHasCorrectOptions() {
    local output
    output="$(_source_and_check)"
    local g_spec
    g_spec="$(echo "$output" | grep ' g$')"
    assertContains 'complete dla "g" musi mieć opcję -o bashdefault' \
        "$g_spec" 'bashdefault'
    assertContains 'complete dla "g" musi mieć opcję -o nospace' \
        "$g_spec" 'nospace'
}

testAsdfCompletionCacheCreated() {
    local output
    output="$(bash -c "
        asdf() {
            if [[ \"\$1\" == 'completion' && \"\$2\" == 'bash' ]]; then
                echo '# asdf bash completion (mock)'
            fi
        }
        export -f asdf
        sdk() { return 0; }; export -f sdk
        export HOME='$_FAKE_HOME'
        . '$PROJECT_ROOT/bash/bash_completion.sh' 2>/dev/null
        [ -f '$_FAKE_HOME/.cache/asdf_bash_completion' ] && echo 'CACHE_CREATED'
    ")"
    assertContains 'plik cache asdf musi zostać stworzony' "$output" 'CACHE_CREATED'
}

testAsdfCompletionCacheNotRegeneratedIfFresh() {
    # Pre-tworzenie cache — przy ponownym sourcowaniu asdf NIE powinno być wołane
    echo '# stale cache' > "$_FAKE_HOME/.cache/asdf_bash_completion"
    local asdf_log
    asdf_log="$(mktemp)"

    bash -c "
        asdf() {
            echo \"CALLED:\$*\" >> '$asdf_log'
            echo '# new completion'
        }
        export -f asdf
        sdk() { return 0; }; export -f sdk
        export HOME='$_FAKE_HOME'
        . '$PROJECT_ROOT/bash/bash_completion.sh' 2>/dev/null
    "

    assertFalse '"asdf completion bash" nie powinno być wywołane gdy cache jest świeży' \
        '[ -s "$asdf_log" ]'
    rm -f "$asdf_log"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
