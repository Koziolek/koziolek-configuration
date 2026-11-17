#!/usr/bin/env bash
# Testy jednostkowe: install_/update_claude_desktop (packages/commons/claude_desktop.sh)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GOOD_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

setUp() {
    _TMP="$(mktemp -d)"
    _LOG="$_TMP/calls.log"
    : >"$_LOG"
    _BIN="$_TMP/bin"
    mkdir -p "$_BIN"
    SUDO=""
    ok() { printf 'OK %s\n' "$*"; }
    warn() { printf 'WARN %s\n' "$*"; }
    info() { printf 'INFO %s\n' "$*"; }
    export CLAUDE_DESKTOP_KEYRING="$_TMP/keyring.asc"
    export CLAUDE_DESKTOP_LIST="$_TMP/claude-desktop.list"
    _FPR="$GOOD_FPR"
    _CANDIDATE="1.2.3"
    _INSTALLED=0
    _ARCH="amd64"
    # shellcheck source=/dev/null
    . "$PROJECT_ROOT/packages/commons/claude_desktop.sh"
}

tearDown() {
    rm -rf "$_TMP"
}

_mock() { # nazwa, ciało skryptu
    printf '#!/bin/sh\necho "%s $*" >> "%s"\n%s\n' "$1" "$_LOG" "$2" >"$_BIN/$1"
    chmod +x "$_BIN/$1"
}

_setup_mocks() {
    _mock apt-get 'exit 0'
    _mock apt-cache "printf 'claude-desktop:\n  Installed: (none)\n  Candidate: $_CANDIDATE\n'"
    _mock dpkg "echo $_ARCH"
    if [ "$_INSTALLED" = 1 ]; then _mock dpkg-query 'printf "install ok installed"'; else _mock dpkg-query 'exit 1'; fi
    _mock curl 'while [ $# -gt 1 ]; do [ "$1" = -fsSLo ] && echo key > "$2"; shift; done; exit 0'
    _mock gpg "echo 'fpr:::::::::$_FPR:'"
}

_run() { # funkcja
    PATH="$_BIN:$PATH" "$1"
}

testInstallAddsRepoAndInstalls() {
    _setup_mocks
    local out
    out=$(_run install_claude_desktop)
    assertTrue "list" "[ -f $CLAUDE_DESKTOP_LIST ]"
    assertTrue "keyring" "[ -f $CLAUDE_DESKTOP_KEYRING ]"
    assertContains "$(cat "$CLAUDE_DESKTOP_LIST")" "signed-by=$CLAUDE_DESKTOP_KEYRING"
    assertContains "$(cat "$_LOG")" "apt-get install -y claude-desktop"
    assertContains "$out" "OK Claude Desktop 1.2.3"
}

testInstallSkipsWhenAlreadyInstalled() {
    _INSTALLED=1
    _setup_mocks
    _run install_claude_desktop >/dev/null
    assertNotContains "$(cat "$_LOG")" "apt-get"
}

testUpdateInstallsWhenMissing() {
    _setup_mocks
    _run update_claude_desktop >/dev/null
    assertContains "$(cat "$_LOG")" "apt-get install -y claude-desktop"
}

testUpdateUpgradesWhenInstalled() {
    _INSTALLED=1
    _setup_mocks
    _run update_claude_desktop >/dev/null
    assertContains "$(cat "$_LOG")" "apt-get install -y claude-desktop"
}

testUpdateWarnsWhenPackageNotInApt() {
    _CANDIDATE="(none)"
    _setup_mocks
    local out rc
    out=$(_run update_claude_desktop)
    rc=$?
    assertEquals 0 "$rc"
    assertContains "$out" "niedostępny w apt"
    assertNotContains "$(cat "$_LOG")" "install -y"
}

testWrongFingerprintRefusesRepo() {
    _FPR="DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF"
    _setup_mocks
    local out
    out=$(_run install_claude_desktop)
    assertContains "$out" "nieoczekiwany fingerprint"
    assertFalse "list" "[ -f $CLAUDE_DESKTOP_LIST ]"
    assertFalse "keyring" "[ -f $CLAUDE_DESKTOP_KEYRING ]"
    assertNotContains "$(cat "$_LOG")" "install -y"
}

testUnsupportedArchIsSkipped() {
    _ARCH="armhf"
    _setup_mocks
    local out
    out=$(_run install_claude_desktop)
    assertContains "$out" "tylko Debian/Ubuntu"
    assertNotContains "$(cat "$_LOG")" "apt-get"
}

testExistingRepoIsNotReadded() {
    _setup_mocks
    : >"$CLAUDE_DESKTOP_LIST"
    : >"$CLAUDE_DESKTOP_KEYRING"
    _run update_claude_desktop >/dev/null
    assertNotContains "$(cat "$_LOG")" "curl"
    assertNotContains "$(cat "$_LOG")" "apt-get -qq update"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
