#!/usr/bin/env bash
# Testy jednostkowe dla git_context (bash/functions.d/110_git-context.sh)
# Uruchomienie: bash tests/test_git_context.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Mock dependencies ──────────────────────────────────────────────────
C_BOLD="" C_NC="" C_YELLOW="" C_CYAN="" C_RED="" C_GREEN=""
export C_BOLD C_NC C_YELLOW C_CYAN C_RED C_GREEN

log_info()  { :; }
log_error() { echo "ERROR: $*" >&2; }
log_warn()  { :; }
log_man()   { :; }
export -f log_info log_error log_warn log_man

# shellcheck source=../bash/functions.d/110_git-context.sh
source "$REPO_ROOT/bash/functions.d/110_git-context.sh"

# ── Test framework ─────────────────────────────────────────────────────
PASS=0
FAIL=0

_ok() {
  echo "ok - $1"
  ((PASS++))
}

_fail() {
  echo "FAIL - $1"
  [[ -n "${2:-}" ]] && echo "       $2"
  ((FAIL++))
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    _ok "$desc"
  else
    _fail "$desc" "expected='$expected' actual='$actual'"
  fi
}

assert_file_exists() {
  local desc="$1" file="$2"
  if [[ -f "$file" ]]; then
    _ok "$desc"
  else
    _fail "$desc" "plik nie istnieje: $file"
  fi
}

assert_file_not_exists() {
  local desc="$1" file="$2"
  if [[ ! -f "$file" ]]; then
    _ok "$desc"
  else
    _fail "$desc" "plik istnieje (nie powinien): $file"
  fi
}

assert_file_contains() {
  local desc="$1" file="$2" pattern="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    _ok "$desc"
  else
    _fail "$desc" "wzorzec '$pattern' nie znaleziony w $file"
  fi
}

assert_file_not_contains() {
  local desc="$1" file="$2" pattern="$3"
  if ! grep -qE "$pattern" "$file" 2>/dev/null; then
    _ok "$desc"
  else
    _fail "$desc" "wzorzec '$pattern' znaleziony w $file (nie powinien)"
  fi
}

# ── Fixtures ───────────────────────────────────────────────────────────
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

setup_git_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
}

REPO_DIR="$TEST_DIR/repo"
CONFIG_FILE="$TEST_DIR/.config/git-context"

setup_git_repo "$REPO_DIR"

# ── Helpers ────────────────────────────────────────────────────────────

run_gc() {
  # Uruchamia git_context z podanym stdin w subshell z HOME=$TEST_DIR
  local input="$1"
  shift
  (
    export HOME="$TEST_DIR"
    cd "$REPO_DIR"
    echo -e "$input" | git_context "$@"
  )
}

# ── Testy: brak pliku konfiguracyjnego ────────────────────────────────

echo ""
echo "=== Brak pliku konfiguracyjnego ==="

rm -f "$CONFIG_FILE"

# 1. użytkownik odmawia → brak pliku, exit 1
run_gc "n" && rc=$? || rc=$?
assert_eq "odmowa tworzenia → exit 1" "1" "$rc"
assert_file_not_exists "odmowa tworzenia → plik nie powstaje" "$CONFIG_FILE"

# 2. użytkownik potwierdza → plik powstaje z sekcją [default]
# stdin: "t" (utwórz), "Jan Kowalski" (name), "jan@example.com" (email), "0" (anuluj wybór kontekstu)
run_gc "t\nJan Kowalski\njan@example.com\n0" && rc=$? || rc=$?
assert_file_exists "potwierdzenie tworzenia → plik istnieje" "$CONFIG_FILE"
assert_file_contains "plik zawiera [default]" "$CONFIG_FILE" "^\[default\]"
assert_file_contains "plik zawiera name" "$CONFIG_FILE" "name\s*=\s*Jan Kowalski"
assert_file_contains "plik zawiera email" "$CONFIG_FILE" "email\s*=\s*jan@example\.com"

# 3. pusty name → loop, ponowne pytanie; drugi input poprawny
rm -f "$CONFIG_FILE"
run_gc "t\n\nJan Kowalski\njan@example.com\n0" && rc=$? || rc=$?
assert_file_exists "pusta nazwa → retry, plik powstaje" "$CONFIG_FILE"
assert_file_contains "pusta nazwa → name zapisany po retry" "$CONFIG_FILE" "name\s*=\s*Jan Kowalski"

# ── Testy: --add ───────────────────────────────────────────────────────

echo ""
echo "=== Tryb --add ==="

# 4. --add bez pliku konfiguracyjnego → exit 1
rm -f "$CONFIG_FILE"
run_gc "" --add && rc=$? || rc=$?
assert_eq "--add bez pliku → exit 1" "1" "$rc"

# 5. --add z istniejącym plikiem → profil dodany
mkdir -p "$(dirname "$CONFIG_FILE")"
printf "[default]\nname  = Test\nemail = test@test.com\n" > "$CONFIG_FILE"
run_gc "work\nJan Pracownik\njan@firma.pl" --add && rc=$? || rc=$?
assert_eq "--add → exit 0" "0" "$rc"
assert_file_contains "--add → sekcja [work] dodana" "$CONFIG_FILE" "^\[work\]"
assert_file_contains "--add → name dodany" "$CONFIG_FILE" "name\s*=\s*Jan Pracownik"
assert_file_contains "--add → email dodany" "$CONFIG_FILE" "email\s*=\s*jan@firma\.pl"
assert_file_contains "--add → istniejący [default] zachowany" "$CONFIG_FILE" "^\[default\]"

# 6. --add z duplikatem → exit 1, plik niezmieniony
lines_before=$(wc -l < "$CONFIG_FILE")
run_gc "default" --add && rc=$? || rc=$?
assert_eq "--add duplikat → exit 1" "1" "$rc"
lines_after=$(wc -l < "$CONFIG_FILE")
assert_eq "--add duplikat → plik niezmieniony (liczba linii)" "$lines_before" "$lines_after"

# 7. --add pusta nazwa → loop, poprawny drugi input
run_gc "\nwork2\nAnia Kowalska\nania@test.pl" --add && rc=$? || rc=$?
assert_eq "--add pusta nazwa → retry działa" "0" "$rc"
assert_file_contains "--add pusta nazwa → profil work2 dodany" "$CONFIG_FILE" "^\[work2\]"

# ── Testy: nie w repozytorium git ─────────────────────────────────────

echo ""
echo "=== Poza repozytorium git ==="

# 8. nie w repo git → exit 1
(
  export HOME="$TEST_DIR"
  cd "$TEST_DIR"
  git_context
) && rc=$? || rc=$?
assert_eq "poza repo git → exit 1" "1" "$rc"

# 9. --add poza repo git → exit 1
(
  export HOME="$TEST_DIR"
  cd "$TEST_DIR"
  git_context --add
) && rc=$? || rc=$?
assert_eq "--add poza repo git → exit 1" "1" "$rc"

# ── Podsumowanie ───────────────────────────────────────────────────────

echo ""
echo "Wyniki: $PASS zaliczonych, $FAIL niezaliczonych"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
