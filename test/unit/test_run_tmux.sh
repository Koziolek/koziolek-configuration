#!/usr/bin/env bash
# Testy jednostkowe: run_tmux z bash/functions.d/000_functions_startup.sh

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"

_FAKE_BIN=''
_CALL_LOG=''

setUp() {
    _FAKE_BIN="$(mktemp -d)"
    _CALL_LOG="$(mktemp)"
}

tearDown() {
    rm -rf "$_FAKE_BIN"
    rm -f "$_CALL_LOG"
}

# Tworzy fałszywy tmux binary; has-session zwraca $1 (0=sesja istnieje, 1=brak)
_make_fake_tmux() {
    local has_session_rc="${1:-0}"
    local log="$_CALL_LOG"
    cat > "$_FAKE_BIN/tmux" << EOF
#!/usr/bin/env bash
echo "\$*" >> "$log"
case "\$1" in
    has-session) exit $has_session_rc ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$_FAKE_BIN/tmux"
}

# Uruchamia run_tmux w izolowanym subshell z fałszywym tmux na czele PATH.
# Domyślnie TMUX jest odkonstrukowany — testy strażnicze ustawiają go przez $extra.
# $1 — opcjonalny dodatkowy kod bash (np. "export TMUX=/tmp/fake.sock")
_run_in_subshell() {
    local extra="${1:-}"
    PATH="$_FAKE_BIN:$PATH" bash -c "
        export MAIN_CONFIGURATION_DIR='$PROJECT_ROOT'
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        unset TMUX
        $extra
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/000_functions_startup.sh' 2>/dev/null
        run_tmux 2>/dev/null
        echo 'AFTER_RUN_TMUX'
    " 2>/dev/null
}

# ---------------------------------------------------------------------------
# Testy strażnicze — run_tmux nie może zastąpić powłoki w tych warunkach
# ---------------------------------------------------------------------------

testRunTmuxDoesNothingWhenInsideTmux() {
    _make_fake_tmux 0
    local result
    result=$(_run_in_subshell "export TMUX='/tmp/fake.sock'")
    assertContains 'run_tmux nie może zastąpić powłoki gdy TMUX jest ustawiony' \
        "$result" 'AFTER_RUN_TMUX'
}

testRunTmuxDoesNothingWhenTermIsScreen() {
    _make_fake_tmux 0
    local result
    result=$(_run_in_subshell "export TERM='screen-256color'")
    assertContains 'run_tmux nie może zastąpić powłoki gdy TERM zawiera screen' \
        "$result" 'AFTER_RUN_TMUX'
}

testRunTmuxDoesNothingWhenTmuxNotInstalled() {
    # Maskuje 'command -v tmux' przez shadowing builtin — bez manipulacji PATH
    local result
    result=$(bash -c "
        command() {
            if [ \"\$1\" = '-v' ] && [ \"\$2\" = 'tmux' ]; then return 1; fi
            builtin command \"\$@\"
        }
        export MAIN_CONFIGURATION_DIR='$PROJECT_ROOT'
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        unset TMUX
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/000_functions_startup.sh' 2>/dev/null
        run_tmux 2>/dev/null
        echo 'AFTER_RUN_TMUX'
    " 2>/dev/null)
    assertContains 'run_tmux nie może zastąpić powłoki gdy tmux jest niedostępny' \
        "$result" 'AFTER_RUN_TMUX'
}

# ---------------------------------------------------------------------------
# Testy logiki sesji
# ---------------------------------------------------------------------------

testRunTmuxCallsSessionInitWhenSessionMissing() {
    _make_fake_tmux 1  # has-session → 1 (sesja nie istnieje)
    _run_in_subshell "" > /dev/null 2>&1 || true
    assertTrue 'gdy brak sesji run_tmux musi wywołać tmux new-session przez session-init.sh' \
        "grep -q 'new-session' '$_CALL_LOG'"
}

testRunTmuxSkipsSessionInitWhenSessionExists() {
    _make_fake_tmux 0  # has-session → 0 (sesja istnieje)
    _run_in_subshell "" > /dev/null 2>&1 || true
    assertFalse 'gdy sesja istnieje tmux new-session nie może być wywołany' \
        "grep -q 'new-session' '$_CALL_LOG'"
}

testRunTmuxAlwaysCallsAttachSession() {
    _make_fake_tmux 0
    _run_in_subshell "" > /dev/null 2>&1 || true
    assertTrue 'run_tmux musi zawsze wywołać tmux attach-session' \
        "grep -q 'attach-session' '$_CALL_LOG'"
}

testRunTmuxAttachesToSessionNamedMain() {
    _make_fake_tmux 0
    _run_in_subshell "" > /dev/null 2>&1 || true
    assertTrue 'run_tmux musi dołączyć do sesji o nazwie main' \
        "grep -q 'attach-session.*main' '$_CALL_LOG'"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
