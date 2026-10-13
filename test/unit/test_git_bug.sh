#!/usr/bin/env bash
# Testy jednostkowe: install_git_bug / update_git_bug (packages/git_bug.sh)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Buduje "wydanie" w $_REL: tarball git-bug_<ver>_linux_amd64.tar.gz z atrapą binarki + checksums.txt.
_make_release() {
    local ver="$1" dir="$_TMP/build/git-bug_${1}_linux_amd64"
    mkdir -p "$dir" "$_REL"
    printf '#!/bin/sh\necho "git-bug v%s abcdef123456 go1.27.1 linux amd64"\n' "$ver" > "$dir/git-bug"
    chmod +x "$dir/git-bug"
    if [ "${_NO_DOCS:-}" != 1 ]; then
        mkdir -p "$dir/man" "$dir/completion/bash" "$dir/completion/zsh"
        echo ".TH GIT-BUG 1 v$ver" > "$dir/man/git-bug.1"
        echo ".TH GIT-BUG-BUG 1 v$ver" > "$dir/man/git-bug-bug.1"
        echo "# bash completion v$ver" > "$dir/completion/bash/git-bug"
        echo "# zsh completion" > "$dir/completion/zsh/git-bug"
    fi
    tar -czf "$_REL/git-bug_${ver}_linux_amd64.tar.gz" -C "$_TMP/build" "git-bug_${ver}_linux_amd64"
    (cd "$_REL" && sha256sum "git-bug_${ver}_linux_amd64.tar.gz" > checksums.txt)
}

setUp() {
    _TMP="$(mktemp -d)"
    _REL="$_TMP/release"
    _CURL_LOG="$_TMP/curl.log"
    : > "$_CURL_LOG"
    export GIT_BUG_INSTALL_DIR="$_TMP/bin"
    export GIT_BUG_DATA_DIR="$_TMP/share"
    _NO_DOCS=""
    _LATEST_URL="https://github.com/git-bug/git-bug/releases/tag/v0.12.0"
    _CURL_FAIL=""
    _UNAME_M="x86_64"
    export PATH_ORIG="$PATH"

    # Atrapa curl: tryb "-w" zwraca URL po przekierowaniu, w pozostałych kopiuje plik z $_REL.
    curl() {
        local out="" url="" w=0 arg
        while [ $# -gt 0 ]; do
            case "$1" in
                -o) out="$2"; shift ;;
                -w) w=1; shift ;;
                -*) ;;
                *) url="$1" ;;
            esac
            shift
        done
        echo "CURL $url" >> "$_CURL_LOG"
        [ -n "$_CURL_FAIL" ] && [[ "$url" == *"$_CURL_FAIL"* ]] && return 22
        if [ "$w" = 1 ]; then
            [ -n "$_LATEST_URL" ] || return 22
            printf '%s' "$_LATEST_URL"
            return 0
        fi
        cp "$_REL/${url##*/}" "$out" 2>/dev/null
    }
    uname() { [ "$1" = "-m" ] && echo "$_UNAME_M" || command uname "$@"; }

    # shellcheck source=/dev/null
    . "$PROJECT_ROOT/packages/git_bug.sh"
}

tearDown() {
    rm -rf "$_TMP"
}

_bin() { echo "$GIT_BUG_INSTALL_DIR/git-bug"; }

testLatestVersionParsedFromRedirect() {
    assertEquals "0.12.0" "$(git_bug_latest_version)"
}

testLatestVersionRejectsGarbageUrl() {
    _LATEST_URL="https://github.com/git-bug/git-bug/releases"
    git_bug_latest_version >/dev/null
    assertNotEquals "kod wyjścia" 0 $?
}

testInstallsWhenMissingWithoutSudo() {
    _make_release 0.12.0
    install_git_bug >/dev/null
    assertTrue "binarka zainstalowana" "[ -x '$(_bin)' ]"
    assertEquals "0.12.0" "$(git_bug_installed_version "$(_bin)")"
}

testUpdatesWhenOlder() {
    _make_release 0.12.0
    mkdir -p "$GIT_BUG_INSTALL_DIR"
    printf '#!/bin/sh\necho "git-bug v0.11.0 abc go linux amd64"\n' > "$(_bin)"
    chmod +x "$(_bin)"
    install_git_bug >/dev/null
    assertEquals "0.12.0" "$(git_bug_installed_version "$(_bin)")"
}

testNoDownloadWhenUpToDate() {
    _make_release 0.12.0
    install_git_bug >/dev/null
    : > "$_CURL_LOG"
    local out
    out=$(install_git_bug)
    assertContains "komunikat" "$out" "git-bug aktualny: v0.12.0"
    assertNotContains "bez pobierania tarballa" "$(cat "$_CURL_LOG")" ".tar.gz"
}

testBadChecksumKeepsOldBinaryAndReturnsZero() {
    _make_release 0.12.0
    echo "0000000000000000000000000000000000000000000000000000000000000000  git-bug_0.12.0_linux_amd64.tar.gz" > "$_REL/checksums.txt"
    mkdir -p "$GIT_BUG_INSTALL_DIR"
    printf '#!/bin/sh\necho "git-bug v0.11.0 abc go linux amd64"\n' > "$(_bin)"
    chmod +x "$(_bin)"
    local out rc
    out=$(install_git_bug); rc=$?
    assertEquals "kod wyjścia" 0 "$rc"
    assertContains "ostrzeżenie" "$out" "suma sha256"
    assertEquals "stara wersja zostaje" "0.11.0" "$(git_bug_installed_version "$(_bin)")"
}

testNetworkFailureOnVersionLookupWarnsAndReturnsZero() {
    _LATEST_URL=""
    local out rc
    out=$(install_git_bug); rc=$?
    assertEquals 0 "$rc"
    assertContains "ostrzeżenie" "$out" "nie udało się ustalić najnowszej wersji"
    assertFalse "nic nie zainstalowano" "[ -e '$(_bin)' ]"
}

testDownloadFailureWarnsAndReturnsZero() {
    _make_release 0.12.0
    _CURL_FAIL=".tar.gz"
    local out rc
    out=$(install_git_bug); rc=$?
    assertEquals 0 "$rc"
    assertContains "ostrzeżenie" "$out" "nie udało się pobrać"
    assertFalse "nic nie zainstalowano" "[ -e '$(_bin)' ]"
}

testUnsupportedArchitectureSkips() {
    _UNAME_M="armv6l"
    local out
    out=$(install_git_bug)
    assertContains "ostrzeżenie" "$out" "nieobsługiwana architektura"
    assertEquals "bez żadnego curl" "" "$(cat "$_CURL_LOG")"
}

testArm64Mapping() {
    _UNAME_M="aarch64"
    assertEquals "arm64" "$(git_bug_arch)"
}

testUpdateInstallsWhenMissing() {
    _make_release 0.12.0
    update_git_bug >/dev/null
    assertTrue "update instaluje, gdy brak" "[ -x '$(_bin)' ]"
}

testInstallsManAndBashCompletion() {
    _make_release 0.12.0
    install_git_bug >/dev/null
    assertTrue "główna strona man" "[ -f '$GIT_BUG_DATA_DIR/man/man1/git-bug.1' ]"
    assertTrue "podstrona man" "[ -f '$GIT_BUG_DATA_DIR/man/man1/git-bug-bug.1' ]"
    assertTrue "completion bash" "[ -f '$GIT_BUG_DATA_DIR/bash-completion/completions/git-bug' ]"
    assertContains "treść z wydania" "$(cat "$GIT_BUG_DATA_DIR/bash-completion/completions/git-bug")" "bash completion v0.12.0"
    assertFalse "zsh nie jest instalowane" "[ -e '$GIT_BUG_DATA_DIR/bash-completion/completions/git-bug.zsh' ]"
}

testUpdateReplacesDocs() {
    _make_release 0.11.0
    _LATEST_URL="https://github.com/git-bug/git-bug/releases/tag/v0.11.0"
    install_git_bug >/dev/null
    _make_release 0.12.0
    _LATEST_URL="https://github.com/git-bug/git-bug/releases/tag/v0.12.0"
    install_git_bug >/dev/null
    assertContains "nowe completion" "$(cat "$GIT_BUG_DATA_DIR/bash-completion/completions/git-bug")" "v0.12.0"
}

testUpToDateWithDocsDoesNotDownload() {
    _make_release 0.12.0
    install_git_bug >/dev/null
    : > "$_CURL_LOG"
    install_git_bug >/dev/null
    assertNotContains "bez pobierania" "$(cat "$_CURL_LOG")" ".tar.gz"
}

testUpToDateBinaryButMissingCompletionBackfills() {
    _make_release 0.12.0
    install_git_bug >/dev/null
    rm -f "$GIT_BUG_DATA_DIR/bash-completion/completions/git-bug"
    local out
    out=$(install_git_bug)
    assertContains "komunikat" "$out" "Uzupełnianie man i completion"
    assertTrue "completion przywrócone" "[ -f '$GIT_BUG_DATA_DIR/bash-completion/completions/git-bug' ]"
}

testMissingDocsInTarballWarnsButInstallsBinary() {
    _NO_DOCS=1
    _make_release 0.12.0
    local out rc
    out=$(install_git_bug); rc=$?
    assertEquals 0 "$rc"
    assertContains "ostrzeżenie man" "$out" "brak stron man"
    assertContains "ostrzeżenie completion" "$out" "brak bash completion"
    assertTrue "binarka jest" "[ -x '$(_bin)' ]"
}

testBadChecksumInstallsNoDocs() {
    _make_release 0.12.0
    echo "0000000000000000000000000000000000000000000000000000000000000000  git-bug_0.12.0_linux_amd64.tar.gz" > "$_REL/checksums.txt"
    install_git_bug >/dev/null
    assertFalse "brak completion" "[ -e '$GIT_BUG_DATA_DIR/bash-completion/completions/git-bug' ]"
    assertFalse "brak man" "[ -e '$GIT_BUG_DATA_DIR/man/man1/git-bug.1' ]"
}

testDataDirDefaultsToXdg() {
    unset GIT_BUG_DATA_DIR
    assertEquals "/x/share" "$(XDG_DATA_HOME=/x/share git_bug_data_dir)"
    assertEquals "$HOME/.local/share" "$(env -u XDG_DATA_HOME bash -c ". '$PROJECT_ROOT/packages/git_bug.sh'; git_bug_data_dir")"
}

testNeverCallsSudo() {
    assertNotContains "git_bug.sh nie używa sudo" "$(grep -v '^ *#' "$PROJECT_ROOT/packages/git_bug.sh" | grep -v 'echo ')" "sudo"
    assertNotContains "git_bug.sh nie używa \$SUDO" "$(cat "$PROJECT_ROOT/packages/git_bug.sh")" '$SUDO'
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
