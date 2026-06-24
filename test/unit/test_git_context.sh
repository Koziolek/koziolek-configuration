#!/usr/bin/env bash
# Testy jednostkowe: git_context (bash/functions.d/110_git-context.sh)
# Wejście interaktywne zastąpione przez printf — pierwszy numer wybiera kontekst,
# drugi (pusty) akceptuje domyślną nazwę projektu.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/110_git-context.sh"

_FAKE_HOME=''
_FAKE_REPO=''

oneTimeSetUp() {
    _FAKE_HOME="$(mktemp -d)"
    mkdir -p "$_FAKE_HOME/.config"

    cat > "$_FAKE_HOME/.config/git-context" <<'EOF'
[work]
name  = Jan Kowalski
email = jan@firma.pl

[personal]
name  = janek99
email = janek@example.com
EOF

    _FAKE_REPO="$(mktemp -d)"
    git -C "$_FAKE_REPO" init -q
    git -C "$_FAKE_REPO" config user.email "stary@test.pl"
    git -C "$_FAKE_REPO" config user.name  "Stary Uzytkownik"
}

oneTimeTearDown() {
    rm -rf "$_FAKE_HOME" "$_FAKE_REPO"
}

setUp() {
    # Czyść lokalne sekcje między testami
    git -C "$_FAKE_REPO" config --local --remove-section user    2>/dev/null || true
    git -C "$_FAKE_REPO" config --local --remove-section project 2>/dev/null || true
}

# Uruchamia git_context cicho — używany gdy interesuje tylko kod wyjścia lub zmiany w git config.
_run_gc() {
    local input="$1"
    ( export HOME="$_FAKE_HOME"
      cd "$_FAKE_REPO"
      printf '%b' "$input" | git_context
    ) >/dev/null 2>/dev/null
}

# Uruchamia git_context i zwraca stdout — używany gdy sprawdzamy zawartość wyjścia.
_run_gc_out() {
    local input="$1"
    ( export HOME="$_FAKE_HOME"
      cd "$_FAKE_REPO"
      printf '%b' "$input" | git_context
    ) 2>/dev/null
}

# ---------------------------------------------------------------------------

testListsAvailableContexts() {
    local output
    output="$(_run_gc_out "0\n")"
    assertContains 'output musi zawierać kontekst "work"'     "$output" 'work'
    assertContains 'output musi zawierać kontekst "personal"' "$output" 'personal'
}

testSetsUserName() {
    _run_gc "1\n\n"
    local name
    name="$(git -C "$_FAKE_REPO" config --local user.name 2>/dev/null || true)"
    assertEquals 'user.name musi być ustawiony na kontekst work' 'Jan Kowalski' "$name"
}

testSetsUserEmail() {
    _run_gc "1\n\n"
    local email
    email="$(git -C "$_FAKE_REPO" config --local user.email 2>/dev/null || true)"
    assertEquals 'user.email musi być ustawiony na kontekst work' 'jan@firma.pl' "$email"
}

testSecondContextSetsCorrectData() {
    _run_gc "2\n\n"
    local name email
    name="$(git -C "$_FAKE_REPO" config --local user.name 2>/dev/null || true)"
    email="$(git -C "$_FAKE_REPO" config --local user.email 2>/dev/null || true)"
    assertEquals 'user.name musi być z kontekstu personal' 'janek99'         "$name"
    assertEquals 'user.email musi być z kontekstu personal' 'janek@example.com' "$email"
}

testHandlesMissingConfigFile() {
    local cfg="$_FAKE_HOME/.config/git-context"
    mv "$cfg" "$cfg.bak"
    local rc=0
    _run_gc "" || rc=$?
    mv "$cfg.bak" "$cfg"
    assertNotEquals 'brak pliku konfiguracyjnego musi zwrócić kod błędu' 0 "$rc"
}

testHandlesInvalidChoiceThenCancel() {
    # 99 → nieprawidłowy wybór (ostrzeżenie), 0 → anulowanie (rc=1)
    local output rc=0
    output="$(_run_gc_out "99\n0\n")" || rc=$?
    assertNotEquals 'anulowanie musi zwrócić kod błędu' 0 "$rc"
    assertContains 'output musi zawierać ostrzeżenie o nieprawidłowym wyborze' \
        "$output" 'Nieprawidłowy'
}

testCancelReturnsNonZero() {
    local rc=0
    _run_gc "0\n" || rc=$?
    assertNotEquals 'wybór 0 (anulowanie) musi zwrócić kod błędu' 0 "$rc"
}

testDoesNotRunOutsideGitRepo() {
    local not_a_repo rc=0
    not_a_repo="$(mktemp -d)"
    ( export HOME="$_FAKE_HOME"
      cd "$not_a_repo"
      printf '' | git_context
    ) >/dev/null 2>/dev/null || rc=$?
    rm -rf "$not_a_repo"
    assertNotEquals 'wywołanie poza repo git musi zwrócić kod błędu' 0 "$rc"
}

# ---------------------------------------------------------------------------
# Tworzenie pliku konfiguracyjnego od zera
# ---------------------------------------------------------------------------

testRefusesCreationReturnsNonZero() {
    local cfg="$_FAKE_HOME/.config/git-context"
    mv "$cfg" "$cfg.bak"
    local rc=0
    ( export HOME="$_FAKE_HOME"
      cd "$_FAKE_REPO"
      printf 'n\n' | git_context
    ) >/dev/null 2>/dev/null || rc=$?
    mv "$cfg.bak" "$cfg"
    assertNotEquals 'odmowa tworzenia pliku musi zwrócić kod błędu' 0 "$rc"
}

testConfirmsCreationMakesFile() {
    local cfg="$_FAKE_HOME/.config/git-context"
    mv "$cfg" "$cfg.bak"
    ( export HOME="$_FAKE_HOME"
      cd "$_FAKE_REPO"
      printf 't\nJan Kowalski\njan@example.com\n0\n' | git_context
    ) >/dev/null 2>/dev/null || true
    local created=false
    [[ -f "$cfg" ]] && created=true
    mv "$cfg.bak" "$cfg"
    assertTrue 'potwierdzenie tworzenia musi stworzyć plik konfiguracyjny' "$created"
}

testConfirmsCreationWritesDefaultSection() {
    local cfg="$_FAKE_HOME/.config/git-context"
    mv "$cfg" "$cfg.bak"
    ( export HOME="$_FAKE_HOME"
      cd "$_FAKE_REPO"
      printf 't\nJan Kowalski\njan@example.com\n0\n' | git_context
    ) >/dev/null 2>/dev/null || true
    local ok=false
    grep -qE '^\[default\]' "$cfg" 2>/dev/null && ok=true
    mv "$cfg.bak" "$cfg"
    assertTrue 'nowo tworzony plik musi zawierać sekcję [default]' "$ok"
}

# ---------------------------------------------------------------------------
# Tryb --add
# ---------------------------------------------------------------------------

testAddWithoutConfigFileReturnsNonZero() {
    local cfg="$_FAKE_HOME/.config/git-context"
    mv "$cfg" "$cfg.bak"
    local rc=0
    ( export HOME="$_FAKE_HOME"
      cd "$_FAKE_REPO"
      printf '' | git_context --add
    ) >/dev/null 2>/dev/null || rc=$?
    mv "$cfg.bak" "$cfg"
    assertNotEquals '--add bez pliku konfiguracyjnego musi zwrócić kod błędu' 0 "$rc"
}

testAddAppendsNewProfile() {
    local cfg="$_FAKE_HOME/.config/git-context"
    local tmp_cfg
    tmp_cfg="$(mktemp)"
    cp "$cfg" "$tmp_cfg"
    ( export HOME="$_FAKE_HOME"
      cd "$_FAKE_REPO"
      printf 'newprofile\nJan Pracownik\njan@firma.pl\n' | git_context --add
    ) >/dev/null 2>/dev/null || true
    local ok=false
    grep -qE '^\[newprofile\]' "$cfg" 2>/dev/null && ok=true
    cp "$tmp_cfg" "$cfg"
    rm -f "$tmp_cfg"
    assertTrue '--add musi dopisać nową sekcję do pliku konfiguracyjnego' "$ok"
}

testAddDuplicateProfileReturnsNonZero() {
    local rc=0
    ( export HOME="$_FAKE_HOME"
      cd "$_FAKE_REPO"
      printf 'work\n' | git_context --add
    ) >/dev/null 2>/dev/null || rc=$?
    assertNotEquals '--add z duplikatem nazwy musi zwrócić kod błędu' 0 "$rc"
}

testAddOutsideGitRepoReturnsNonZero() {
    local not_a_repo rc=0
    not_a_repo="$(mktemp -d)"
    ( export HOME="$_FAKE_HOME"
      cd "$not_a_repo"
      printf '' | git_context --add
    ) >/dev/null 2>/dev/null || rc=$?
    rm -rf "$not_a_repo"
    assertNotEquals '--add poza repo git musi zwrócić kod błędu' 0 "$rc"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
