#!/usr/bin/env bash
# Testy jednostkowe: git_vomit, git_bleeh (git/git_functions.sh)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

SUPPRESS_SOURCING=1 . "$PROJECT_ROOT/git/git_functions.sh" 2>/dev/null || true

_CAPTURED_COMMIT_MSG=''
_MOCK_BRANCH=''
_MOCK_PREFIX=''
_MOCK_COMMIT_COUNT=0
_MOCK_OLD_MESSAGES=''

log_info()  { :; }
log_error() { :; }
log_warn()  { :; }
log_man()   { :; }

git_current_branch()        { echo "$_MOCK_BRANCH"; }
git_commit_message_prefix() { echo "$_MOCK_PREFIX"; }

git() {
    case "$1" in
        add|push|reset) : ;;
        ci|commit)
            local i next
            for (( i=2; i<=$#; i++ )); do
                if [[ "${!i}" == "-m" ]]; then
                    next=$((i+1))
                    _CAPTURED_COMMIT_MSG="${!next}"
                    return 0
                fi
            done
            ;;
        log)
            if [[ "$*" == *"--oneline"* ]]; then
                [[ "$_MOCK_COMMIT_COUNT" -gt 0 ]] && seq 1 "$_MOCK_COMMIT_COUNT" | sed 's/.*/x/'
            elif [[ "$*" == *"--format=%s"* ]]; then
                echo "$_MOCK_OLD_MESSAGES"
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
    _MOCK_BRANCH=''
    _MOCK_PREFIX=''
    _MOCK_COMMIT_COUNT=0
    _MOCK_OLD_MESSAGES=''
}

# ---------------------------------------------------------------------------
# git_vomit
# ---------------------------------------------------------------------------

testVomitAddsPrefix() {
    _MOCK_BRANCH="feature/APB-11-opis"
    _MOCK_PREFIX="feat: APB-11"
    git_vomit "moja zmiana"
    assertEquals 'branch z prefiksem → prefix + wiadomość' \
        "feat: APB-11 moja zmiana" "$_CAPTURED_COMMIT_MSG"
}

testVomitNoPrefixOnMaster() {
    _MOCK_BRANCH="master"
    _MOCK_PREFIX=""
    git_vomit "hotfix na masterze"
    assertEquals 'branch bez prefiksu → sama wiadomość' \
        "hotfix na masterze" "$_CAPTURED_COMMIT_MSG"
}

testVomitFixBranchPrefix() {
    _MOCK_BRANCH="fix/OOO-111-cos"
    _MOCK_PREFIX="fix: OOO-111"
    git_vomit "naprawa bledu"
    assertEquals 'fix branch → fix prefix' \
        "fix: OOO-111 naprawa bledu" "$_CAPTURED_COMMIT_MSG"
}

# ---------------------------------------------------------------------------
# git_bleeh
# ---------------------------------------------------------------------------

testBleehNoPreviousCommitsAddsPrefix() {
    _MOCK_BRANCH="feature/APB-22-nowa"
    _MOCK_PREFIX="feat: APB-22"
    _MOCK_COMMIT_COUNT=0
    _MOCK_OLD_MESSAGES=""
    git_bleeh "pierwsza zmiana"
    assertEquals 'brak poprzednich commitów → prefix + wiadomość' \
        "feat: APB-22 pierwsza zmiana" "$_CAPTURED_COMMIT_MSG"
}

testBleehSquashesOldMessages() {
    _MOCK_BRANCH="feature/APB-33-squash"
    _MOCK_PREFIX="feat: APB-33"
    _MOCK_COMMIT_COUNT=2
    _MOCK_OLD_MESSAGES=$'feat: APB-33 krok jeden\nfeat: APB-33 krok dwa'
    git_bleeh "squash wszystkiego"
    local expected=$'feat: APB-33 krok jeden\nfeat: APB-33 krok dwa\nfeat: APB-33 squash wszystkiego'
    assertEquals 'squash z prefixem w nowej wiadomości' "$expected" "$_CAPTURED_COMMIT_MSG"
}

testBleehNoPrefixOnMaster() {
    _MOCK_BRANCH="master"
    _MOCK_PREFIX=""
    _MOCK_COMMIT_COUNT=0
    _MOCK_OLD_MESSAGES=""
    git_bleeh "prosta zmiana"
    assertEquals 'brak prefixu → sama wiadomość bez spacji' \
        "prosta zmiana" "$_CAPTURED_COMMIT_MSG"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
