#!/usr/bin/env bash
# Testy jednostkowe: git_vomit, git_bleeh, git_armageddon (git/git_functions.sh)

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

# --- mocki dodatkowe: git_armageddon ---------------------------------------
_MOCK_INSIDE_REPO=1
_MOCK_HAS_REMOTE=1
_MOCK_ABBREV_BRANCH=''
_MOCK_DIRTY=0
_MOCK_DIRTY_STAGED=0
_MOCK_BACKUP_EXISTS=0
_MOCK_OLD_COMMITS=5
_CAPTURED_PUSH_ARGS=''
_PUSH_CALLS=0
_CAPTURED_BACKUP_BRANCH_CREATED=''
_CAPTURED_RENAME_ARGS=''
_CAPTURED_CHECKOUT_ORPHAN=0

log_info()  { :; }
log_error() { :; }
log_warn()  { :; }
log_man()   { :; }

git_current_branch()        { echo "$_MOCK_BRANCH"; }
git_commit_message_prefix() { echo "$_MOCK_PREFIX"; }

git() {
    case "$1" in
        add) : ;;
        push)
            shift
            _CAPTURED_PUSH_ARGS="$*"
            _PUSH_CALLS=$((_PUSH_CALLS + 1))
            ;;
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
        rev-parse)
            case "$2" in
                --is-inside-work-tree) [ "$_MOCK_INSIDE_REPO" = 1 ] && { echo true; return 0; } || return 1 ;;
                --show-toplevel) echo "$_TESTDIR" ;;
                --abbrev-ref) echo "$_MOCK_ABBREV_BRANCH" ;;
            esac
            ;;
        remote)
            [[ "$2" == "get-url" ]] || return 0
            [ "$_MOCK_HAS_REMOTE" = 1 ] && { echo "git@example.com:x/y.git"; return 0; } || return 1
            ;;
        diff)
            [[ "$*" == *"--cached"* ]] && return "$_MOCK_DIRTY_STAGED"
            return "$_MOCK_DIRTY"
            ;;
        show-ref)
            [ "$_MOCK_BACKUP_EXISTS" = 1 ] && return 0 || return 1
            ;;
        rev-list)
            [[ "$*" == *"--count"* ]] && echo "$_MOCK_OLD_COMMITS"
            ;;
        checkout)
            [[ "$2" == "--orphan" ]] && _CAPTURED_CHECKOUT_ORPHAN=1
            ;;
        branch)
            if [[ "$2" == "-M" ]]; then
                _CAPTURED_RENAME_ARGS="$3 $4"
            else
                _CAPTURED_BACKUP_BRANCH_CREATED="$2"
            fi
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

    _MOCK_INSIDE_REPO=1
    _MOCK_HAS_REMOTE=1
    _MOCK_ABBREV_BRANCH="feature/APB-1-opis"
    _MOCK_DIRTY=0
    _MOCK_DIRTY_STAGED=0
    _MOCK_BACKUP_EXISTS=0
    _MOCK_OLD_COMMITS=5
    _CAPTURED_PUSH_ARGS=''
    _PUSH_CALLS=0
    _CAPTURED_BACKUP_BRANCH_CREATED=''
    _CAPTURED_RENAME_ARGS=''
    _CAPTURED_CHECKOUT_ORPHAN=0
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
# git_armageddon
# ---------------------------------------------------------------------------

testArmageddonAbortsIfNotGitRepo() {
    _MOCK_INSIDE_REPO=0
    git_armageddon -y
    assertEquals 'brak pusha' 0 "$_PUSH_CALLS"
}

testArmageddonAbortsIfNoRemote() {
    _MOCK_HAS_REMOTE=0
    git_armageddon -y
    assertEquals 'brak pusha' 0 "$_PUSH_CALLS"
}

testArmageddonAbortsOnDetachedHead() {
    _MOCK_ABBREV_BRANCH="HEAD"
    git_armageddon -y
    assertEquals 'brak pusha' 0 "$_PUSH_CALLS"
}

testArmageddonAbortsOnDirtyWorktree() {
    _MOCK_DIRTY=1
    git_armageddon -y
    assertEquals 'brak pusha' 0 "$_PUSH_CALLS"
}

testArmageddonAbortsOnDirtyIndex() {
    _MOCK_DIRTY_STAGED=1
    git_armageddon -y
    assertEquals 'brak pusha' 0 "$_PUSH_CALLS"
}

testArmageddonAbortsIfBackupBranchExists() {
    _MOCK_BACKUP_EXISTS=1
    git_armageddon -y
    assertEquals 'brak pusha' 0 "$_PUSH_CALLS"
    assertEquals 'backup nie tworzony ponownie' '' "$_CAPTURED_BACKUP_BRANCH_CREATED"
}

testArmageddonNonTtyWithoutYesAborts() {
    git_armageddon < /dev/null
    assertEquals 'brak pusha' 0 "$_PUSH_CALLS"
}

testArmageddonHappyPathWithFlagYes() {
    git_armageddon -y
    assertEquals 'orphan checkout wykonany' 1 "$_CAPTURED_CHECKOUT_ORPHAN"
    assertEquals 'commit z domyslnym komunikatem' 'Initial commit' "$_CAPTURED_COMMIT_MSG"
    assertEquals 'backup utworzony' 'backup-old-history' "$_CAPTURED_BACKUP_BRANCH_CREATED"
    assertEquals 'branch -M na docelowa galaz' "__armageddon__ feature/APB-1-opis" "$_CAPTURED_RENAME_ARGS"
    assertEquals 'jeden push (bez tagow)' 1 "$_PUSH_CALLS"
    assertEquals 'force push docelowej galezi' "--force origin feature/APB-1-opis" "$_CAPTURED_PUSH_ARGS"
}

testArmageddonHappyPathWithAssumeYesEnv() {
    export GIT_ASSUME_YES=1
    git_armageddon
    assertEquals 1 "$_PUSH_CALLS"
}

testArmageddonCustomMessage() {
    git_armageddon -y -m "swiezy start"
    assertEquals "swiezy start" "$_CAPTURED_COMMIT_MSG"
}

testArmageddonPushTagsFlag() {
    git_armageddon -y -t
    assertEquals 'dwa pushe (branch + tagi)' 2 "$_PUSH_CALLS"
    assertEquals 'ostatni push to tagi' "--force --tags origin" "$_CAPTURED_PUSH_ARGS"
}

testArmageddonNoPushTagsByDefault() {
    git_armageddon -y
    assertEquals 1 "$_PUSH_CALLS"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
