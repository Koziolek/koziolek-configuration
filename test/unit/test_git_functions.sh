#!/usr/bin/env bash
# Testy jednostkowe: git_vomit, git_bleeh (git/git_functions.sh)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

SUPPRESS_SOURCING=1 . "$PROJECT_ROOT/git/git_functions.sh" 2>/dev/null || true

_CAPTURED_COMMIT_MSG=''
_CAPTURED_COMMIT_DONE=0
_MOCK_BRANCH=''
_MOCK_PREFIX=''
_MOCK_COMMIT_COUNT=0
_MOCK_RESET_DONE=0
_TESTDIR=''

log_info()  { :; }
log_error() { :; }
log_warn()  { :; }
log_man()   { :; }

git_current_branch()        { echo "$_MOCK_BRANCH"; }
git_commit_message_prefix() { echo "$_MOCK_PREFIX"; }

git() {
    case "$1" in
        add|push) : ;;
        reset) _MOCK_RESET_DONE=1 ;;
        ci|commit)
            local i next
            for (( i=2; i<=$#; i++ )); do
                if [[ "${!i}" == "-m" ]]; then
                    next=$((i+1)); _CAPTURED_COMMIT_MSG="${!next}"; _CAPTURED_COMMIT_DONE=1; return 0
                elif [[ "${!i}" == "-F" ]]; then
                    next=$((i+1)); _CAPTURED_COMMIT_MSG="$(cat "${!next}")"; _CAPTURED_COMMIT_DONE=1; return 0
                fi
            done
            ;;
        log)
            if [[ "$*" == *"--oneline"* ]]; then
                [[ "$_MOCK_COMMIT_COUNT" -gt 0 ]] && seq 1 "$_MOCK_COMMIT_COUNT" | sed 's/.*/x/'
            fi
            ;;
        symbolic-ref)
            [[ "$*" == *"refs/remotes/origin/HEAD"* ]] && echo "refs/remotes/origin/master"
            ;;
        *) : ;;
    esac
}

setUp() {
    _CAPTURED_COMMIT_MSG=''
    _CAPTURED_COMMIT_DONE=0
    _MOCK_BRANCH=''
    _MOCK_PREFIX=''
    _MOCK_COMMIT_COUNT=0
    _MOCK_RESET_DONE=0
    unset GIT_ASSUME_YES
    _TESTDIR="$(mktemp -d)"
    cd "$_TESTDIR" || fail "cd do testdir"
}

tearDown() {
    cd "$PROJECT_ROOT" || true
    [ -n "$_TESTDIR" ] && rm -rf "$_TESTDIR"
}

_write_msg_file() { printf '%s\n' "$@" > commit-message.txt; }

# ---------------------------------------------------------------------------
# git_vomit — z parametrami (plik zawsze wykorzystany)
# ---------------------------------------------------------------------------

testVomitParamsAddsPrefix() {
    _MOCK_BRANCH="feature/APB-11-opis"
    _MOCK_PREFIX="feat: APB-11"
    git_vomit "moja zmiana"
    assertEquals "feat: APB-11 moja zmiana" "$_CAPTURED_COMMIT_MSG"
}

testVomitParamsNoPrefixOnMaster() {
    _MOCK_BRANCH="master"
    _MOCK_PREFIX=""
    git_vomit "hotfix na masterze"
    assertEquals "hotfix na masterze" "$_CAPTURED_COMMIT_MSG"
}

testVomitParamsPrependedToExistingFile() {
    _MOCK_BRANCH="feature/APB-11-opis"
    _MOCK_PREFIX="feat: APB-11"
    _write_msg_file "stara tresc" "drugi wiersz"
    git_vomit "nowy naglowek"
    assertEquals $'feat: APB-11 nowy naglowek\nstara tresc\ndrugi wiersz' "$_CAPTURED_COMMIT_MSG"
}

testVomitClearsFileAfterCommit() {
    _MOCK_BRANCH="master"; _MOCK_PREFIX=""
    git_vomit "cokolwiek"
    assertTrue 'plik istnieje' '[ -f commit-message.txt ]'
    assertEquals 'plik pusty' "" "$(cat commit-message.txt)"
}

# ---------------------------------------------------------------------------
# git_vomit — bez parametrów, plik jako źródło
# ---------------------------------------------------------------------------

testVomitFileUsedWithAssumeYes() {
    _MOCK_BRANCH="master"; _MOCK_PREFIX=""
    export GIT_ASSUME_YES=1
    _write_msg_file "fix: JIRA-1 z pliku"
    git_vomit
    assertEquals "fix: JIRA-1 z pliku" "$_CAPTURED_COMMIT_MSG"
}

testVomitFileNoPrefixGetsBranchPrefix() {
    _MOCK_BRANCH="feature/APB-11-opis"
    _MOCK_PREFIX="feat: APB-11"
    export GIT_ASSUME_YES=1
    _write_msg_file "wiadomosc bez prefiksu"
    git_vomit
    assertEquals "feat: APB-11 wiadomosc bez prefiksu" "$_CAPTURED_COMMIT_MSG"
}

testVomitFileWithPrefixUnchanged() {
    _MOCK_BRANCH="feature/APB-11-opis"
    _MOCK_PREFIX="feat: APB-11"
    export GIT_ASSUME_YES=1
    _write_msg_file "feat: RECZNY-9 wlasny prefiks"
    git_vomit
    assertEquals "feat: RECZNY-9 wlasny prefiks" "$_CAPTURED_COMMIT_MSG"
}

testVomitEmptyFileNoParamsAborts() {
    _MOCK_BRANCH="master"; _MOCK_PREFIX=""
    export GIT_ASSUME_YES=1
    : > commit-message.txt
    git_vomit
    assertEquals 'brak commita' 0 "$_CAPTURED_COMMIT_DONE"
}

testVomitMissingFileNoParamsAborts() {
    _MOCK_BRANCH="master"; _MOCK_PREFIX=""
    export GIT_ASSUME_YES=1
    git_vomit
    assertEquals 'brak commita' 0 "$_CAPTURED_COMMIT_DONE"
}

testVomitFlagYesOverridesEnv() {
    _MOCK_BRANCH="master"; _MOCK_PREFIX=""
    export GIT_ASSUME_YES=0
    _write_msg_file "fix: A-1 z flaga"
    git_vomit -y
    assertEquals "fix: A-1 z flaga" "$_CAPTURED_COMMIT_MSG"
}

testVomitNonTtyWithoutYesAborts() {
    _MOCK_BRANCH="master"; _MOCK_PREFIX=""
    export GIT_ASSUME_YES=0
    _write_msg_file "fix: A-1 tresc"
    git_vomit < /dev/null
    assertEquals 'brak commita w trybie nie-tty bez -y' 0 "$_CAPTURED_COMMIT_DONE"
}

# ---------------------------------------------------------------------------
# git_bleeh
# ---------------------------------------------------------------------------

testBleehNoPreviousCommits() {
    _MOCK_BRANCH="feature/APB-22-nowa"
    _MOCK_PREFIX="feat: APB-22"
    _MOCK_COMMIT_COUNT=0
    git_bleeh "pierwsza zmiana"
    assertEquals "feat: APB-22 pierwsza zmiana" "$_CAPTURED_COMMIT_MSG"
    assertEquals 'brak resetu' 0 "$_MOCK_RESET_DONE"
}

testBleehOverwritesHistory() {
    _MOCK_BRANCH="feature/APB-33-squash"
    _MOCK_PREFIX="feat: APB-33"
    _MOCK_COMMIT_COUNT=3
    git_bleeh "squash wszystkiego"
    assertEquals 'plik nadpisuje historie — brak starych %s' \
        "feat: APB-33 squash wszystkiego" "$_CAPTURED_COMMIT_MSG"
    assertEquals 'reset wykonany' 1 "$_MOCK_RESET_DONE"
}

testBleehFileUsedWithAssumeYes() {
    _MOCK_BRANCH="feature/APB-33-squash"
    _MOCK_PREFIX="feat: APB-33"
    _MOCK_COMMIT_COUNT=2
    export GIT_ASSUME_YES=1
    _write_msg_file "feat: APB-33 z pliku" "" "opis w body"
    git_bleeh
    assertEquals $'feat: APB-33 z pliku\n\nopis w body' "$_CAPTURED_COMMIT_MSG"
}

testBleehClearsFileAfterCommit() {
    _MOCK_BRANCH="master"; _MOCK_PREFIX=""
    _MOCK_COMMIT_COUNT=0
    git_bleeh "cokolwiek"
    assertEquals 'plik pusty' "" "$(cat commit-message.txt)"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
