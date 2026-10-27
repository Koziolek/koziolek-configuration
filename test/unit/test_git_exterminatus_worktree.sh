#!/usr/bin/env bash
# Testy jednostkowe: git_exterminatus_worktree (git/git_functions.sh).
# Prawdziwy git na repozytoriach w mktemp (bare origin + klon); bez mocków git.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

SUPPRESS_SOURCING=1 . "$PROJECT_ROOT/git/git_functions.sh" 2>/dev/null || true

# Komunikaty do pliku jako "klucz argumenty" (jak w innych testach mockujących log_*).
log_info() { echo "INFO $*" >>"$_LOG"; }
log_warn() { echo "WARN $*" >>"$_LOG"; }
log_error() { echo "ERROR $*" >>"$_LOG"; }
log_debug() { echo "DEBUG $*" >>"$_LOG"; }
log_man() { :; }

setUp() {
    _TMP="$(mktemp -d)"
    _LOG="$_TMP/log"
    : >"$_LOG"
    export HOME="$_TMP/home"
    mkdir -p "$HOME"
    export GIT_CONFIG_GLOBAL="$_TMP/gitconfig"
    git config --global user.name tester
    git config --global user.email tester@example.invalid
    git config --global init.defaultBranch master
    git config --global commit.gpgsign false

    _ORIGIN="$_TMP/origin.git"
    _REPO="$_TMP/repo"
    git init -q --bare "$_ORIGIN"
    git clone -q "$_ORIGIN" "$_REPO" 2>/dev/null
    cd "$_REPO" || return 1
    echo base >base.txt
    git add base.txt && git commit -q -m base
    git push -q -u origin master
    git remote set-head origin master >/dev/null
    mkdir -p .worktrees
}

tearDown() {
    cd / || true
    rm -rf "$_TMP"
}

# _new_wt <gałąź> [plik] — worktree .worktrees/<gałąź> z jednym commitem, wypchnięty na origin
_new_wt() {
    local b="$1" f="${2:-$1.txt}"
    git worktree add -q -b "$b" ".worktrees/$b" origin/master
    echo "$b" >".worktrees/$b/$f"
    git -C ".worktrees/$b" add "$f"
    git -C ".worktrees/$b" commit -q -m "$b"
    git -C ".worktrees/$b" push -q -u origin "$b" 2>/dev/null
}

# Squash merge na origin/master (nowy commit o tej samej zmianie, bez rodzica z gałęzi)
_squash_merge() {
    local b="$1" clone="$_TMP/other"
    git clone -q "$_ORIGIN" "$clone" 2>/dev/null
    git -C "$clone" merge -q --squash "origin/$b" >/dev/null 2>&1
    git -C "$clone" commit -q -m "squash $b (#1)"
    git -C "$clone" push -q origin master
}

_regular_merge() {
    local b="$1" clone="$_TMP/other"
    git clone -q "$_ORIGIN" "$clone" 2>/dev/null
    git -C "$clone" merge -q --no-ff -m "merge $b" "origin/$b" >/dev/null 2>&1
    git -C "$clone" push -q origin master
}

_wt_exists() { [ -d "$_REPO/.worktrees/$1" ]; }
_local_branch() { git -C "$_REPO" show-ref --verify -q "refs/heads/$1"; }
_remote_branch() { git -C "$_ORIGIN" show-ref --verify -q "refs/heads/$1"; }

testRemovesSquashMergedWorktree() {
    _new_wt feat-a
    _squash_merge feat-a
    git_exterminatus_worktree
    assertFalse 'worktree usunięty' "_wt_exists feat-a"
    assertFalse 'lokalna gałąź usunięta' "_local_branch feat-a"
    assertFalse 'zdalna gałąź usunięta' "_remote_branch feat-a"
}

testRemovesRegularMergedWorktree() {
    _new_wt feat-b
    _regular_merge feat-b
    git_exterminatus_worktree
    assertFalse "_wt_exists feat-b"
    assertFalse "_local_branch feat-b"
    assertFalse "_remote_branch feat-b"
}

testKeepsUnmergedWorktree() {
    _new_wt feat-open
    git_exterminatus_worktree
    assertTrue 'worktree zostaje' "_wt_exists feat-open"
    assertTrue 'lokalna gałąź zostaje' "_local_branch feat-open"
    assertTrue 'zdalna gałąź zostaje' "_remote_branch feat-open"
    assertContains "$(cat "$_LOG")" "git.worktree_nothing_to_remove"
}

testRemovesOnlyMergedWhenMixed() {
    _new_wt merged-one
    _new_wt open-one
    _squash_merge merged-one
    git_exterminatus_worktree
    assertFalse "_wt_exists merged-one"
    assertTrue "_wt_exists open-one"
    assertTrue "_remote_branch open-one"
    assertContains "$(cat "$_LOG")" "git.worktree_summary 1"
}

testKeepsFreshWorktreeWithoutOwnCommits() {
    git worktree add -q -b fresh .worktrees/fresh origin/master
    git_exterminatus_worktree
    assertTrue 'świeża gałąź nie jest "zmergowana"' "_wt_exists fresh"
    assertTrue "_local_branch fresh"
}

testKeepsMergedBranchWithNewCommitAfterMerge() {
    _new_wt feat-c
    _squash_merge feat-c
    echo more >.worktrees/feat-c/more.txt
    git -C .worktrees/feat-c add more.txt
    git -C .worktrees/feat-c commit -q -m more
    git_exterminatus_worktree
    assertTrue 'dodatkowy commit po merge = niezmergowane' "_wt_exists feat-c"
    assertTrue "_local_branch feat-c"
}

testDryRunRemovesNothing() {
    _new_wt feat-d
    _squash_merge feat-d
    git_exterminatus_worktree --dry-run
    assertTrue "_wt_exists feat-d"
    assertTrue "_local_branch feat-d"
    assertTrue "_remote_branch feat-d"
    assertContains "$(cat "$_LOG")" "git.worktree_would_remove"
}

testDirtyWorktreeIsKeptWithWarning() {
    _new_wt feat-e
    _squash_merge feat-e
    echo wip >.worktrees/feat-e/untracked.txt
    git_exterminatus_worktree
    assertTrue 'brudny worktree zostaje' "_wt_exists feat-e"
    assertTrue 'gałąź zostaje' "_local_branch feat-e"
    assertContains "$(cat "$_LOG")" "git.worktree_remove_failed"
}

testSkipsCurrentWorktree() {
    _new_wt feat-f
    _squash_merge feat-f
    cd .worktrees/feat-f || return 1
    git_exterminatus_worktree
    assertTrue "_wt_exists feat-f"
    assertContains "$(cat "$_LOG")" "git.worktree_skip_current"
}

testWorksFromInsideOtherWorktree() {
    _new_wt feat-g
    _new_wt feat-h
    _squash_merge feat-g
    cd .worktrees/feat-h || return 1
    git_exterminatus_worktree
    assertFalse "_wt_exists feat-g"
    assertTrue "_wt_exists feat-h"
}

testMainCheckoutBranchIsNeverRemoved() {
    git_exterminatus_worktree
    assertTrue 'master zostaje' "_local_branch master"
    assertTrue "[ -d '$_REPO/.git' ]"
}

testLocalOnlyBranchWithoutRemoteIsRemovedLocally() {
    git worktree add -q -b local-only .worktrees/local-only origin/master
    echo x >.worktrees/local-only/x.txt
    git -C .worktrees/local-only add x.txt
    git -C .worktrees/local-only commit -q -m x
    _squash_merge_local() {
        git -C "$_REPO" merge -q --squash local-only >/dev/null 2>&1
        git -C "$_REPO" commit -q -m "squash local-only"
        git -C "$_REPO" push -q origin master
    }
    _squash_merge_local
    git_exterminatus_worktree
    assertFalse "_wt_exists local-only"
    assertFalse "_local_branch local-only"
    assertNotContains "$(cat "$_LOG")" "git.worktree_remote_delete_failed"
}

testBadArgumentReturns2() {
    git_exterminatus_worktree --nope
    assertEquals 2 "$?"
    assertContains "$(cat "$_LOG")" "git.usage_git_exterminatus_worktree"
}

testOutsideRepoFails() {
    cd "$_TMP" || return 1
    git_exterminatus_worktree
    assertEquals 1 "$?"
    assertContains "$(cat "$_LOG")" "git.not_a_git_repository"
}

testNoRemoteUsesLocalDefaultBranch() {
    git remote remove origin
    git worktree add -q -b loc .worktrees/loc master
    echo y >.worktrees/loc/y.txt
    git -C .worktrees/loc add y.txt
    git -C .worktrees/loc commit -q -m y
    git merge -q --no-ff -m "merge loc" loc >/dev/null 2>&1
    git_exterminatus_worktree
    assertFalse "_wt_exists loc"
    assertFalse "_local_branch loc"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
