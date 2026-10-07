#!/usr/bin/env bash
# Testy jednostkowe: link_claude_skills (packages/link_claude_skills.sh)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

setUp() {
    _TMP="$(mktemp -d)"
    export KLAUDYNA_DIR="$_TMP/klaudyna"
    export CLAUDE_SKILLS_DIR="$_TMP/claude/skills"
    export KLAUDYNA_URL="git@example.invalid:klaudyna.git"
    _GIT_LOG="$_TMP/git.log"
    : > "$_GIT_LOG"
    unset _LS_REMOTE_RC
    # shellcheck source=/dev/null
    . "$PROJECT_ROOT/packages/link_claude_skills.sh"

    git() {
        echo "GIT $*" >> "$_GIT_LOG"
        [ "$1" = "ls-remote" ] && return "${_LS_REMOTE_RC:-0}"
        if [ "$1" = "clone" ]; then
            mkdir -p "$3/skills/alpha" "$3/skills/beta"
        fi
        return 0
    }
}

tearDown() {
    rm -rf "$_TMP"
}

_make_repo() {
    mkdir -p "$KLAUDYNA_DIR/skills/alpha" "$KLAUDYNA_DIR/skills/beta"
}

testLinksEverySkill() {
    _make_repo
    link_claude_skills >/dev/null
    assertTrue "alpha symlink" "[ -L '$CLAUDE_SKILLS_DIR/alpha' ]"
    assertTrue "beta symlink" "[ -L '$CLAUDE_SKILLS_DIR/beta' ]"
    assertEquals "$KLAUDYNA_DIR/skills/alpha" "$(readlink "$CLAUDE_SKILLS_DIR/alpha")"
}

testIdempotent() {
    _make_repo
    link_claude_skills >/dev/null
    link_claude_skills >/dev/null
    assertEquals "$KLAUDYNA_DIR/skills/beta" "$(readlink "$CLAUDE_SKILLS_DIR/beta")"
    assertEquals "brak zagnieżdżonego linka" "no" "$([ -e "$KLAUDYNA_DIR/skills/alpha/alpha" ] && echo yes || echo no)"
}

testKeepsRealDirectory() {
    _make_repo
    mkdir -p "$CLAUDE_SKILLS_DIR/alpha"
    link_claude_skills >/dev/null
    assertTrue "alpha zostaje katalogiem" "[ -d '$CLAUDE_SKILLS_DIR/alpha' ] && [ ! -L '$CLAUDE_SKILLS_DIR/alpha' ]"
    assertTrue "beta zlinkowany" "[ -L '$CLAUDE_SKILLS_DIR/beta' ]"
}

testClonesWhenMissing() {
    link_claude_skills >/dev/null
    assertTrue "git clone wywołany" "grep -q '^GIT clone ' '$_GIT_LOG'"
    assertTrue "alpha symlink" "[ -L '$CLAUDE_SKILLS_DIR/alpha' ]"
}

testNoAccessSkipsWithoutError() {
    _LS_REMOTE_RC=128
    link_claude_skills >/dev/null
    assertEquals "return 0" 0 $?
    assertFalse "bez clone" "grep -q '^GIT clone ' '$_GIT_LOG'"
    assertFalse "bez katalogu skilli" "[ -d '$CLAUDE_SKILLS_DIR' ]"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
