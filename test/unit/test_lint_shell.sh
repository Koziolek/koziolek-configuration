#!/usr/bin/env bash
# Testy jednostkowe: tools/lint-shell.sh (linthis: ShellCheck + shfmt).
# linthis/shellcheck/shfmt to atrapy w hermetycznym PATH (loguje argumenty); wybór plików testowany na
# prawdziwych repozytoriach git w mktemp. Testy z prawdziwym linthis pomijają się, gdy go nie ma.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$PROJECT_ROOT/tools/lint-shell.sh"

setUp() {
    _TMP="$(mktemp -d)"
    _BIN="$_TMP/bin"
    _LOG="$_TMP/linthis.log"
    mkdir -p "$_BIN"
    : >"$_LOG"
    cd "$_TMP" || return 1 # poprzedni test mógł zostawić nas w usuniętym katalogu
    # Hermetyczny PATH: prawdziwe linthis/shellcheck/shfmt hosta nie mogą wpływać na wynik.
    local t src
    for t in bash env git sed sort grep cat dirname; do
        src="$(command -v "$t" 2>/dev/null)" && ln -s "$src" "$_BIN/$t"
    done
    _mock_tool linthis 'echo "$*" >> "$LINTHIS_LOG"; exit "${LINTHIS_RC:-0}"'
    _mock_tool shellcheck 'exit 0'
    _mock_tool shfmt 'exit 0'
    export LINTHIS_LOG="$_LOG"
    unset LINTHIS_RC
    _OLD_PATH="$PATH"
    _OUT=""
    _RC=0
}

tearDown() {
    PATH="$_OLD_PATH"
    endSkipping
    cd "$PROJECT_ROOT" || return 1
    rm -rf "$_TMP"
}

_mock_tool() {
    printf '#!/usr/bin/env bash\n%s\n' "$2" >"$_BIN/$1"
    chmod +x "$_BIN/$1"
}

# _run <args…> — uruchamia skrypt w $PWD z hermetycznym PATH; wynik w _OUT i _RC
_run() {
    _OUT="$(PATH="$_BIN" bash "$SCRIPT" "$@" 2>&1)"
    _RC=$?
}

_linthis_args() { cat "$_LOG"; }

# Repo z origin: master (a.sh, d.sh, README.md) + gałąź feature ze zmianami
_make_repo() {
    git init -q --bare "$_TMP/origin.git"
    git clone -q "$_TMP/origin.git" "$_TMP/repo" 2>/dev/null
    cd "$_TMP/repo" || return 1
    git config user.email t@t
    git config user.name t
    git checkout -q -b master
    printf '#!/bin/bash\n' >a.sh
    printf '#!/bin/bash\n' >d.sh
    printf '#!/bin/bash\n' >b.sh
    echo x >README.md
    git add . && git commit -q -m init
    git push -q origin master 2>/dev/null
    git remote set-head origin master >/dev/null 2>&1
    git checkout -q -b feature
    echo '# zmiana' >>a.sh && git commit -q -am "zmiana a.sh"
    echo '# zmiana' >>b.sh       # niezacommitowana
    echo y >>README.md           # nie-shell
    printf '#!/bin/bash\n' >c.sh # nowy, nieśledzony
}

# ---------------------------------------------------------------- argumenty i środowisko

testHelpPrintsUsageAndExitsZero() {
    _run --help
    assertEquals 0 "$_RC"
    assertContains "$_OUT" "Użycie: tools/lint-shell.sh"
    assertContains "$_OUT" "--check"
}

testUnknownOptionExitsUsageError() {
    _run --nie-ma
    assertEquals 64 "$_RC"
    assertContains "$_OUT" "nieznana opcja"
    assertEquals "linthis nie uruchomiony" "" "$(_linthis_args)"
}

testBaseWithoutArgumentExitsUsageError() {
    _run --base
    assertEquals 64 "$_RC"
}

testMissingFileExitsUsageError() {
    _run --check "$_TMP/nie-ma.sh"
    assertEquals 64 "$_RC"
    assertContains "$_OUT" "nie ma pliku"
}

testMissingToolsExitsWithInstallHint() {
    rm "$_BIN/shfmt" "$_BIN/linthis"
    _run --check x.sh
    assertEquals 127 "$_RC"
    assertContains "$_OUT" "brak w PATH: linthis shfmt"
    assertContains "$_OUT" "cargo install --locked linthis"
    assertContains "$_OUT" "lang_packages.sh"
}

testNotAGitRepoWithoutFilesExitsUsageError() {
    cd "$_TMP" || return 1
    _run --check
    assertEquals 64 "$_RC"
    assertContains "$_OUT" "nie jest repozytorium git"
}

# ---------------------------------------------------------------- flagi linthis

testCheckPassesCheckOnlyAndNoFormat() {
    : >"$_TMP/f.sh"
    _run --check "$_TMP/f.sh"
    assertEquals 0 "$_RC"
    assertContains "$(_linthis_args)" "--check-only"
    assertNotContains "$(_linthis_args)" "--format-only"
}

testFormatPassesFormatOnly() {
    : >"$_TMP/f.sh"
    _run --format "$_TMP/f.sh"
    assertContains "$(_linthis_args)" "--format-only"
    assertNotContains "$(_linthis_args)" "--check-only"
}

testDefaultRunsBothWithoutModeFlags() {
    : >"$_TMP/f.sh"
    _run "$_TMP/f.sh"
    assertNotContains "$(_linthis_args)" "--check-only"
    assertNotContains "$(_linthis_args)" "--format-only"
}

testBothFlagsMeanBoth() {
    : >"$_TMP/f.sh"
    _run --check --format "$_TMP/f.sh"
    assertNotContains "$(_linthis_args)" "--check-only"
    assertNotContains "$(_linthis_args)" "--format-only"
}

testAlwaysShellLintOnlySavesResults() {
    : >"$_TMP/f.sh"
    _run --check "$_TMP/f.sh"
    assertContains "$(_linthis_args)" "--lang shell --checks lint"
    assertNotContains "$(_linthis_args)" "--no-save-result"
}

testExplicitFilesBecomeIncludes() {
    : >"$_TMP/x.sh"
    : >"$_TMP/y.sh"
    _run --check "$_TMP/x.sh" "$_TMP/y.sh"
    assertContains "$(_linthis_args)" "-i $_TMP/x.sh -i $_TMP/y.sh"
}

testLinthisFailurePropagatesExitCode() {
    : >"$_TMP/f.sh"
    export LINTHIS_RC=1
    _run --check "$_TMP/f.sh"
    assertEquals 1 "$_RC"
    assertContains "$_OUT" "kodem 1"
}

# ---------------------------------------------------------------- wybór plików

testDefaultScopeIsChangedAgainstDefaultBranch() {
    _make_repo
    _run --check
    assertEquals 0 "$_RC"
    local a
    a="$(_linthis_args)"
    assertContains "zacommitowana zmiana" "$a" "-i a.sh"
    assertContains "niezacommitowana zmiana" "$a" "-i b.sh"
    assertContains "nowy, nieśledzony" "$a" "-i c.sh"
    assertNotContains "niezmieniony" "$a" "d.sh"
    assertNotContains "nie-shell" "$a" "README"
}

testAllTakesEveryTrackedShellFile() {
    _make_repo
    _run --check --all
    local a
    a="$(_linthis_args)"
    assertContains "$a" "-i a.sh"
    assertContains "$a" "-i d.sh"
    assertNotContains "nieśledzony nie wchodzi do --all" "$a" "c.sh"
}

testBaseOptionOverridesDefaultBranch() {
    _make_repo
    _run --check --base HEAD
    local a
    a="$(_linthis_args)"
    assertContains "zmiany względem HEAD: tylko working tree" "$a" "-i b.sh"
    assertNotContains "commit a.sh jest już w HEAD" "$a" "a.sh"
}

testNoChangedFilesSkipsLinthis() {
    _make_repo
    git checkout -q master 2>/dev/null
    git clean -fdq
    git checkout -q -- .
    _run --check
    assertEquals 0 "$_RC"
    assertContains "$_OUT" "brak plików .sh"
    assertEquals "" "$(_linthis_args)"
}

testFilesWithSpacesAreHandled() {
    _make_repo
    printf '#!/bin/bash\n' >"spacja w nazwie.sh"
    _run --check
    assertContains "$(_linthis_args)" "-i spacja w nazwie.sh"
}

testWorksFromSubdirectory() {
    _make_repo
    mkdir sub
    cd sub || return 1
    _run --check
    assertEquals 0 "$_RC"
    assertContains "ścieżki względem korzenia repo" "$(_linthis_args)" "-i a.sh"
}

# ---------------------------------------------------------------- prawdziwy linthis (pomijane bez niego)

_real_tools_or_skip() {
    local t
    for t in linthis shellcheck shfmt; do
        command -v "$t" >/dev/null 2>&1 || startSkipping
    done
}

_run_real() {
    _OUT="$(bash "$SCRIPT" "$@" 2>&1)"
    _RC=$?
}

testRealCheckPassesOnCleanFileAndFailsOnShellcheckError() {
    _real_tools_or_skip
    printf '#!/usr/bin/env bash\necho ok\n' >"$_TMP/good.sh"
    printf '#!/usr/bin/env bash\nif [ ; then\n  echo\nfi\n' >"$_TMP/broken.sh"
    _run_real --check "$_TMP/good.sh"
    assertEquals "czysty plik" 0 "$_RC"
    _run_real --check "$_TMP/broken.sh"
    assertNotEquals "błąd ShellCheck" 0 "$_RC"
}

testRealFormatIsIdempotentAndUsesEditorconfig() {
    _real_tools_or_skip
    cp "$PROJECT_ROOT/.editorconfig" "$_TMP/.editorconfig"
    printf '#!/usr/bin/env bash\nif true; then\necho   hi\n  fi\n' >"$_TMP/ugly.sh"
    _run_real --format "$_TMP/ugly.sh"
    assertEquals 0 "$_RC"
    assertEquals "wcięcie 4 spacje z .editorconfig" "    echo hi" "$(sed -n 3p "$_TMP/ugly.sh")"
    local before after
    before="$(cksum <"$_TMP/ugly.sh")"
    _run_real --format "$_TMP/ugly.sh"
    after="$(cksum <"$_TMP/ugly.sh")"
    assertEquals "drugi format nic nie zmienia" "$before" "$after"
}

testRealCheckDoesNotModifyFiles() {
    _real_tools_or_skip
    printf '#!/usr/bin/env bash\nif true; then\necho   hi\n  fi\n' >"$_TMP/ugly.sh"
    local before
    before="$(cksum <"$_TMP/ugly.sh")"
    _run_real --check "$_TMP/ugly.sh"
    assertEquals "check nie formatuje" "$before" "$(cksum <"$_TMP/ugly.sh")"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
