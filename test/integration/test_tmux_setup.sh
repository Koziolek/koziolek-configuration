#!/usr/bin/env bash
# Testy integracyjne: tmux/main.sh — symlink ~/.tmux.conf i struktura plików

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"

_FAKE_HOME=''

oneTimeSetUp() {
    _FAKE_HOME="$(mktemp -d)"
}

oneTimeTearDown() {
    rm -rf "$_FAKE_HOME"
}

# Sourcuje tmux/main.sh w izolowanym subshell z podanym HOME; wypisuje EXIT:<kod>
_source_tmux_main() {
    HOME="$_FAKE_HOME" bash -c "
        export MAIN_CONFIGURATION_DIR='$PROJECT_ROOT'
        export TMUX_CONFIGURATION_DIR='$PROJECT_ROOT/tmux'
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        . '$PROJECT_ROOT/tmux/main.sh' 2>/dev/null
        echo 'EXIT:'\$?
    " 2>/dev/null
}

# ---------------------------------------------------------------------------
# Pliki repo
# ---------------------------------------------------------------------------

testTmuxConfFileExistsInRepo() {
    assertTrue 'tmux/tmux.conf musi istnieć w repo' \
        '[ -f "$PROJECT_ROOT/tmux/tmux.conf" ]'
}

testSessionInitScriptExistsInRepo() {
    assertTrue 'tmux/session-init.sh musi istnieć w repo' \
        '[ -f "$PROJECT_ROOT/tmux/session-init.sh" ]'
}

testSessionInitScriptIsExecutable() {
    assertTrue 'tmux/session-init.sh musi mieć bit wykonywalny' \
        '[ -x "$PROJECT_ROOT/tmux/session-init.sh" ]'
}

testTmuxMainShExistsInRepo() {
    assertTrue 'tmux/main.sh musi istnieć w repo' \
        '[ -f "$PROJECT_ROOT/tmux/main.sh" ]'
}

# ---------------------------------------------------------------------------
# Symlink ~/.tmux.conf
# ---------------------------------------------------------------------------

testTmuxMainLoadsWithoutError() {
    local result
    result=$(_source_tmux_main)
    assertContains 'tmux/main.sh musi załadować się z kodem 0' "$result" 'EXIT:0'
}

testTmuxMainCreatesSymlink() {
    _source_tmux_main > /dev/null
    assertTrue '~/.tmux.conf musi być symlinklem po załadowaniu tmux/main.sh' \
        '[ -L "$_FAKE_HOME/.tmux.conf" ]'
}

testTmuxMainSymlinkPointsToRepoConf() {
    _source_tmux_main > /dev/null
    local target
    target="$(readlink "$_FAKE_HOME/.tmux.conf" 2>/dev/null)"
    assertEquals 'symlink musi wskazywać na tmux/tmux.conf w repo' \
        "$PROJECT_ROOT/tmux/tmux.conf" "$target"
}

testTmuxMainIsIdempotent() {
    _source_tmux_main > /dev/null
    _source_tmux_main > /dev/null
    assertTrue '~/.tmux.conf musi istnieć po dwukrotnym wywołaniu' \
        '[ -L "$_FAKE_HOME/.tmux.conf" ]'
    local target
    target="$(readlink "$_FAKE_HOME/.tmux.conf" 2>/dev/null)"
    assertEquals 'symlink musi nadal wskazywać na repo po dwukrotnym wywołaniu' \
        "$PROJECT_ROOT/tmux/tmux.conf" "$target"
}

# ---------------------------------------------------------------------------
# Zawartość session-init.sh
# ---------------------------------------------------------------------------

_session_init() { cat "$PROJECT_ROOT/tmux/session-init.sh"; }

testSessionInitDefinesWindowServer() {
    assertContains 'session-init.sh musi definiować WIN_SERVER' \
        "$(_session_init)" 'WIN_SERVER="SERVER"'
}

testSessionInitDefinesWindowState() {
    assertContains 'session-init.sh musi definiować WIN_STATE' \
        "$(_session_init)" 'WIN_STATE="STATE"'
}

testSessionInitDefinesWindowHome() {
    assertContains 'session-init.sh musi definiować WIN_HOME' \
        "$(_session_init)" 'WIN_HOME="HOME"'
}

testSessionInitHasFunctionCreateWindowServer() {
    assertContains 'session-init.sh musi zawierać create_window_server()' \
        "$(_session_init)" 'create_window_server()'
}

testSessionInitHasFunctionCreateWindowState() {
    assertContains 'session-init.sh musi zawierać create_window_state()' \
        "$(_session_init)" 'create_window_state()'
}

testSessionInitHasFunctionCreateWindowHome() {
    assertContains 'session-init.sh musi zawierać create_window_home()' \
        "$(_session_init)" 'create_window_home()'
}

testSessionInitDefaultFocusIsHome() {
    assertContains 'session-init.sh musi ustawiać fokus na WIN_HOME' \
        "$(_session_init)" 'select-window -t "$SESSION:$WIN_HOME"'
}

# ---------------------------------------------------------------------------
# Zawartość tmux.conf
# ---------------------------------------------------------------------------

testTmuxConfContainsCwdBindings() {
    assertContains 'tmux.conf musi zawierać bind c z pane_current_path' \
        "$(cat "$PROJECT_ROOT/tmux/tmux.conf")" 'pane_current_path'
}

testTmuxConfContainsUpdateEnvironment() {
    assertContains 'tmux.conf musi zawierać update-environment dla Claude Code' \
        "$(cat "$PROJECT_ROOT/tmux/tmux.conf")" 'CLAUDE_CODE_SSE_PORT'
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
