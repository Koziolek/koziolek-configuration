#!/usr/bin/env bash
# Testy jednostkowe dla git_vomit i git_bleeh (git/git_functions.sh)
# Uruchomienie: bash tests/test_git_functions.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Test framework ─────────────────────────────────────────────────────
PASS=0
FAIL=0

_ok()   { echo "ok - $1"; ((PASS++)); }
_fail() { echo "FAIL - $1"; [[ -n "${2:-}" ]] && echo "       $2"; ((FAIL++)); }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    _ok "$desc"
  else
    _fail "$desc" "expected='$expected' actual='$actual'"
  fi
}

# ── Załaduj funkcje (SUPPRESS_SOURCING=1 pomija ładowanie konfiguracji bash) ──
C_BOLD="" C_NC="" C_YELLOW="" C_CYAN="" C_RED="" C_GREEN="" C_LBLUE=""
export C_BOLD C_NC C_YELLOW C_CYAN C_RED C_GREEN C_LBLUE

SUPPRESS_SOURCING=1 source "$REPO_ROOT/git/git_functions.sh" 2>/dev/null || true

# ── Mock dependencies (definiowane PO source, żeby nadpisać oryginały) ─
log_info()  { :; }
log_error() { echo "ERROR: $*" >&2; }
log_warn()  { :; }
log_man()   { :; }

CAPTURED_COMMIT_MSG=""
MOCK_BRANCH=""
MOCK_PREFIX=""
MOCK_COMMIT_COUNT=0
MOCK_OLD_MESSAGES=""

git_current_branch()        { echo "$MOCK_BRANCH"; }
git_commit_message_prefix() { echo "$MOCK_PREFIX"; }

git() {
  case "$1" in
    add)    : ;;
    push)   : ;;
    reset)  : ;;
    ci|commit)
      local i next
      for ((i=2; i<=$#; i++)); do
        if [[ "${!i}" == "-m" ]]; then
          next=$((i+1))
          CAPTURED_COMMIT_MSG="${!next}"
          return 0
        fi
      done
      ;;
    log)
      if [[ "$*" == *"--oneline"* ]]; then
        [ "$MOCK_COMMIT_COUNT" -gt 0 ] && seq 1 "$MOCK_COMMIT_COUNT" | sed 's/.*/x/'
      elif [[ "$*" == *"--format=%s"* ]]; then
        echo "$MOCK_OLD_MESSAGES"
      fi
      ;;
    symbolic-ref)
      [[ "$*" == *"refs/remotes/origin/HEAD"* ]] && echo "refs/remotes/origin/master"
      ;;
    *) : ;;
  esac
}

# ── Testy git_vomit ────────────────────────────────────────────────────

echo ""
echo "=== git_vomit ==="

# 1. branch z prefiksem → prefix + spacja + wiadomość
MOCK_BRANCH="feature/APB-11-opis"
MOCK_PREFIX="feat: APB-11"
CAPTURED_COMMIT_MSG=""
git_vomit "moja zmiana"
assert_eq "vomit: prefix + wiadomość" "feat: APB-11 moja zmiana" "$CAPTURED_COMMIT_MSG"

# 2. branch bez prefiksu (np. master) → sama wiadomość
MOCK_BRANCH="master"
MOCK_PREFIX=""
CAPTURED_COMMIT_MSG=""
git_vomit "hotfix na masterze"
assert_eq "vomit: brak prefixu → sama wiadomość" "hotfix na masterze" "$CAPTURED_COMMIT_MSG"

# 3. fix branch → poprawny prefix
MOCK_BRANCH="fix/OOO-111-cos"
MOCK_PREFIX="fix: OOO-111"
CAPTURED_COMMIT_MSG=""
git_vomit "naprawa bledu"
assert_eq "vomit: fix prefix" "fix: OOO-111 naprawa bledu" "$CAPTURED_COMMIT_MSG"

# ── Testy git_bleeh ────────────────────────────────────────────────────

echo ""
echo "=== git_bleeh ==="

# 4. brak poprzednich commitów → sam nowy komunikat z prefixem
MOCK_BRANCH="feature/APB-22-nowa"
MOCK_PREFIX="feat: APB-22"
MOCK_COMMIT_COUNT=0
MOCK_OLD_MESSAGES=""
CAPTURED_COMMIT_MSG=""
git_bleeh "pierwsza zmiana"
assert_eq "bleeh: brak poprzednich → prefix + wiadomość" "feat: APB-22 pierwsza zmiana" "$CAPTURED_COMMIT_MSG"

# 5. poprzednie commity → stare wiadomości + nowa z prefixem
MOCK_BRANCH="feature/APB-33-squash"
MOCK_PREFIX="feat: APB-33"
MOCK_COMMIT_COUNT=2
MOCK_OLD_MESSAGES=$'feat: APB-33 krok jeden\nfeat: APB-33 krok dwa'
CAPTURED_COMMIT_MSG=""
git_bleeh "squash wszystkiego"
EXPECTED=$'feat: APB-33 krok jeden\nfeat: APB-33 krok dwa\nfeat: APB-33 squash wszystkiego'
assert_eq "bleeh: squash z prefixem w nowej wiadomości" "$EXPECTED" "$CAPTURED_COMMIT_MSG"

# 6. bleeh bez prefixu → sama wiadomość bez spacji na początku
MOCK_BRANCH="master"
MOCK_PREFIX=""
MOCK_COMMIT_COUNT=0
MOCK_OLD_MESSAGES=""
CAPTURED_COMMIT_MSG=""
git_bleeh "prosta zmiana"
assert_eq "bleeh: brak prefixu → sama wiadomość" "prosta zmiana" "$CAPTURED_COMMIT_MSG"

# ── Podsumowanie ───────────────────────────────────────────────────────

echo ""
echo "Wyniki: $PASS zaliczonych, $FAIL niezaliczonych"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
