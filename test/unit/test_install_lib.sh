#!/usr/bin/env bash
# Testy jednostkowe: install_lib (bash/functions.d/095_function_misc.sh)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"

_FAKE_TOOLS=''
_GIT_LOG=''

oneTimeSetUp() {
    _FAKE_TOOLS="$(mktemp -d)"
    _GIT_LOG="$(mktemp)"
    export WORKSPACE_TOOLS="$_FAKE_TOOLS"
}

oneTimeTearDown() {
    rm -rf "$_FAKE_TOOLS"
    rm -f "$_GIT_LOG"
}

setUp() {
    : > "$_GIT_LOG"
    unset _LS_REMOTE_RC
    # shellcheck source=/dev/null
    . "$PROJECT_ROOT/bash/functions.d/095_function_misc.sh"

    # Mock git — loguje wywołania zamiast wykonywać. `ls-remote` zwraca kod
    # sterowany $_LS_REMOTE_RC (domyślnie sukces) — do testów flagi -p.
    git() {
        echo "GIT $*" >> "$_GIT_LOG"
        [ "$1" = "ls-remote" ] && return "${_LS_REMOTE_RC:-0}"
        return 0
    }
}

tearDown() {
    unset -f git 2>/dev/null || true
}

# ---------------------------------------------------------------------------

testFastPathSkipsCloneWhenDirExists() {
    mkdir -p "$_FAKE_TOOLS/mylib"
    install_lib -r "https://example.com/mylib.git" -t "mylib" >/dev/null 2>&1
    assertFalse 'fast-path nie powinien wołać git clone' '[ -s "$_GIT_LOG" ]'
    rm -rf "$_FAKE_TOOLS/mylib"
}

testFastPathNoSourceWithoutXFlag() {
    mkdir -p "$_FAKE_TOOLS/mylib"
    echo 'SOURCED_MARKER=yes' > "$_FAKE_TOOLS/mylib/init.sh"
    unset SOURCED_MARKER
    install_lib -r "https://example.com/mylib.git" -t "mylib" -e "init.sh" >/dev/null 2>&1
    assertNull 'bez -x plik nie powinien być sourcowany' "${SOURCED_MARKER:-}"
    rm -rf "$_FAKE_TOOLS/mylib"
}

testFastPathSourcesFileWhenXFlagSet() {
    mkdir -p "$_FAKE_TOOLS/mylib"
    echo 'SOURCED_MARKER=yes' > "$_FAKE_TOOLS/mylib/init.sh"
    unset SOURCED_MARKER
    install_lib -r "https://example.com/mylib.git" -t "mylib" -e "init.sh" -x >/dev/null 2>&1
    assertEquals 'z -x plik powinien być sourcowany' 'yes' "${SOURCED_MARKER:-}"
    unset SOURCED_MARKER
    rm -rf "$_FAKE_TOOLS/mylib"
}

testReturnsErrorWithoutRepoUrl() {
    local rc=0
    install_lib -t "somedir" >/dev/null 2>&1 || rc=$?
    assertNotEquals 'brak -r musi zwrócić kod błędu' 0 "$rc"
}

testClonesWhenDirAbsent() {
    # Katalog nie istnieje — install_lib powinno wywołać git clone
    rm -rf "$_FAKE_TOOLS/newlib"
    install_lib -r "https://example.com/newlib.git" -t "newlib" >/dev/null 2>&1 || true
    assertContains 'git clone powinien być wywołany' "$(cat "$_GIT_LOG")" 'clone'
}

testTargetDirDerivedFromRepoName() {
    # Bez -t katalog docelowy to basename repo bez .git
    rm -rf "$_FAKE_TOOLS/barrepo"
    install_lib -r "https://example.com/barrepo.git" >/dev/null 2>&1 || true
    assertContains 'git clone powinien użyć nazwy z repo URL' \
        "$(cat "$_GIT_LOG")" "barrepo"
}

testFastPathReturnsZero() {
    mkdir -p "$_FAKE_TOOLS/fastlib"
    local rc=99
    install_lib -r "https://example.com/fastlib.git" -t "fastlib" >/dev/null 2>&1
    rc=$?
    assertEquals 'fast-path musi zwracać 0' 0 "$rc"
    rm -rf "$_FAKE_TOOLS/fastlib"
}

# --- -p (bezpieczne klonowanie repo prywatnego) -----------------------------

testSafeFlagSkipsCloneWhenNoAccess() {
    rm -rf "$_FAKE_TOOLS/privlib"
    _LS_REMOTE_RC=1
    local rc=99 out
    out=$(install_lib -r "https://example.com/privlib.git" -t "privlib" -p 2>&1)
    rc=$?
    assertEquals 'brak dostępu (-p) NIE jest błędem — return 0' 0 "$rc"
    assertContains 'ma być komunikat o braku dostępu' "$out" 'brak dostępu'
    assertNotContains 'clone NIE powinno być wywołane bez dostępu' "$(cat "$_GIT_LOG")" 'clone'
    unset _LS_REMOTE_RC
}

testSafeFlagClonesWhenAccessOk() {
    rm -rf "$_FAKE_TOOLS/privlib2"
    _LS_REMOTE_RC=0
    install_lib -r "https://example.com/privlib2.git" -t "privlib2" -p >/dev/null 2>&1
    assertContains 'z dostępem (-p) clone MA być wywołane' "$(cat "$_GIT_LOG")" 'clone'
    unset _LS_REMOTE_RC
}

testWithoutSafeFlagSkipsAccessCheck() {
    rm -rf "$_FAKE_TOOLS/publiclib"
    _LS_REMOTE_RC=1
    install_lib -r "https://example.com/publiclib.git" -t "publiclib" >/dev/null 2>&1
    assertNotContains 'bez -p nie sprawdzamy dostępu (ls-remote)' "$(cat "$_GIT_LOG")" 'ls-remote'
    assertContains 'bez -p clone leci normalnie mimo _LS_REMOTE_RC=1' "$(cat "$_GIT_LOG")" 'clone'
    unset _LS_REMOTE_RC
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
