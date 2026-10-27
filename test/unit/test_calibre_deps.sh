#!/usr/bin/env bash
# Testy jednostkowe: calibre_install_deps (packages/commons/calibre_deps.sh)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

setUp() {
    _TMP="$(mktemp -d)"
    _LOG="$_TMP/pm.log"
    : >"$_LOG"
    _BIN="$_TMP/bin"
    mkdir -p "$_BIN"
    SUDO=""
    # shellcheck source=/dev/null
    . "$PROJECT_ROOT/packages/commons/calibre_deps.sh"
}

tearDown() {
    rm -rf "$_TMP"
}

# Mock menedżera pakietów w restrykcyjnym PATH (tylko to, co zainstalowane "w systemie").
_mock_pm() {
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit %s\n' "$1" "$_LOG" "${2:-0}" >"$_BIN/$1"
    chmod +x "$_BIN/$1"
}

_run() {
    PATH="$_BIN" calibre_install_deps
}

testAptInstallsLibxcbCursor() {
    _mock_pm apt-get
    _run >/dev/null
    assertContains "$(cat "$_LOG")" "apt-get install -qqy libxcb-cursor0"
}

testYumInstallsXcbUtilCursor() {
    _mock_pm yum
    _run >/dev/null
    assertContains "$(cat "$_LOG")" "yum install -y xcb-util-cursor"
}

testAptWinsWhenBothPresent() {
    _mock_pm apt-get
    _mock_pm yum
    _run >/dev/null
    assertNotContains "$(cat "$_LOG")" "yum"
}

testFailureWarnsAndReturnsZero() {
    _mock_pm apt-get 100
    local out rc
    out=$(_run)
    rc=$?
    assertEquals 0 "$rc"
    assertContains "$out" "libxcb-cursor0 niezainstalowany"
}

testNoPackageManagerIsNoop() {
    local out rc
    out=$(_run)
    rc=$?
    assertEquals 0 "$rc"
    assertEquals "" "$out"
}

testUsesSudoPrefix() {
    _mock_pm sudo
    _mock_pm apt-get
    SUDO="sudo"
    _run >/dev/null
    assertContains "$(cat "$_LOG")" "sudo apt-get install -qqy libxcb-cursor0"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
