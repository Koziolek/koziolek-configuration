#!/usr/bin/env bash
# Testy jednostkowe: install.sh — bootstrap = git → klon → initial_packages.sh z klona.
# Wybór skryptu per system NIE należy już do install.sh (patrz test_packages_dispatch.sh);
# tu sprawdzamy tylko klonowanie i przekazanie sterowania. Całkowicie offline: PROJECT_CLONE_URL
# wskazuje lokalne repo w katalogu tymczasowym, a HOME jest podmieniony.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_SH="$PROJECT_ROOT/install.sh"
PROJECT='koziolek-configuration'

setUp() {
    _TMP="$(mktemp -d)"
    _HOME="$_TMP/home"
    _SRC="$_TMP/src"
    mkdir -p "$_HOME" "$_SRC"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    (
        cd "$_SRC" || exit 1
        git init -q -b master .
        # Atrapa dispatchera: raportuje, skąd została uruchomiona i na jakiej jest gałęzi.
        cat > initial_packages.sh <<'SCRIPT'
#!/usr/bin/env bash
echo "DISPATCHER dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) branch=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --abbrev-ref HEAD)"
SCRIPT
        git add . && git commit -q -m init
        git branch feature
    )
}

tearDown() { rm -rf "$_TMP"; }

_install() {
    # _install [extra env assignments...] ; stdout+stderr, kod -> $?
    env HOME="$_HOME" PROJECT_CLONE_URL="$_SRC" "$@" bash "$INSTALL_SH" 2>&1
}

testClonesRepoAndRunsDispatcherFromClone() {
    local out
    out=$(_install)
    assertContains "dispatcher uruchomiony z klona (przez symlink ~/.projekt)" "$out" "DISPATCHER dir=$_HOME/.$PROJECT branch=master"
    assertTrue "katalog klona" "[ -d '$_HOME/workspace/$PROJECT/.git' ]"
    assertTrue "symlink ~/.$PROJECT" "[ -L '$_HOME/.$PROJECT' ]"
    assertEquals "symlink wskazuje na klon" "$_HOME/workspace/$PROJECT" "$(readlink "$_HOME/.$PROJECT")"
}

testSecondRunDoesNotTouchExistingClone() {
    _install >/dev/null
    echo "lokalna zmiana" > "$_HOME/workspace/$PROJECT/local.txt"
    local out
    out=$(_install)
    assertContains "dispatcher dalej uruchomiony" "$out" "DISPATCHER"
    assertTrue "lokalny plik nietknięty" "[ -f '$_HOME/workspace/$PROJECT/local.txt' ]"
}

testRefSelectsBranchOnFreshClone() {
    local out
    out=$(_install KOZIOLEK_REF=feature)
    assertContains "klon z wybranej gałęzi" "$out" "branch=feature"
}

testRefDoesNotSwitchExistingClone() {
    _install >/dev/null
    local out
    out=$(_install KOZIOLEK_REF=feature)
    assertContains "istniejący klon zostaje na swojej gałęzi" "$out" "branch=master"
}

testMissingDispatcherAborts() {
    git -C "$_SRC" rm -q initial_packages.sh && git -C "$_SRC" commit -q -m rm
    local out rc=0
    out=$(_install) || rc=$?
    assertNotEquals "kod wyjścia" 0 "$rc"
    assertContains "komunikat" "$out" "Brak"
}

testCloneFailureAborts() {
    local rc=0
    env HOME="$_HOME" PROJECT_CLONE_URL="$_TMP/nie-ma-takiego-repo" bash "$INSTALL_SH" >/dev/null 2>&1 || rc=$?
    assertNotEquals 0 "$rc"
}

testInstallShDoesNotFetchFromGithubRaw() {
    local code
    code=$(grep -v '^ *#' "$INSTALL_SH")
    assertNotContains "brak raw.githubusercontent poza komentarzami" "$code" "raw.githubusercontent"
    assertNotContains "brak curl -… (pobierania)" "$code" "curl -"
    assertNotContains "brak wget" "$code" "wget"
}

testInstallShDoesNotDuplicateSystemDetection() {
    local code
    code=$(grep -v '^ *#' "$INSTALL_SH")
    assertNotContains "wykrywanie systemu tylko w initial_packages.sh" "$code" "detect_context"
    assertNotContains "bez własnego mapowania skryptów" "$code" "initial_packages_ubuntu"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
