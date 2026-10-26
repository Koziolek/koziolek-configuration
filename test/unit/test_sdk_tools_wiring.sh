#!/usr/bin/env bash
# Testy jednostkowe: podpięcie listy narzędzi sdkman/asdf (#165, #167) w packages/*/{install,update}.sh.
# Pilnuje, że każdy system woła helpery z commons i nie ma już narzędzi wpisanych na sztywno.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYSTEMS="ubuntu vanilla redhat mac"

# _line <plik> <wzorzec> — numer pierwszej linii (poza komentarzami) pasującej do wzorca; pusty = brak
_line() {
    grep -nE "$2" "$PROJECT_ROOT/packages/$1" | grep -vE '^[0-9]+:[[:space:]]*#' | head -1 | cut -d: -f1
}

_count() {
    grep -E "$2" "$PROJECT_ROOT/packages/$1" | grep -cvE '^[[:space:]]*#'
}

testEverySystemSourcesApplyHelpers() {
    local s f
    for s in $SYSTEMS; do
        for f in install.sh update.sh; do
            assertNotEquals "$s/$f: brak source sdk_tools_apply.sh" "" "$(_line "$s/$f" 'source .*sdk_tools_apply\.sh')"
        done
    done
}

testInstallersCallHelpersInOrder() {
    local s asdf tools lang sdkman
    for s in $SYSTEMS; do
        asdf="$(_line "$s/install.sh" '^install_asdf$')"
        tools="$(_line "$s/install.sh" '^install_asdf_tools$')"
        lang="$(_line "$s/install.sh" '^install_lang_packages$')"
        sdkman="$(_line "$s/install.sh" '^install_sdkman$')"
        assertNotEquals "$s/install.sh: brak install_asdf_tools" "" "$tools"
        assertTrue "$s/install.sh: asdf przed narzędziami asdf" "[ '${asdf:-999}' -lt '${tools:-0}' ]"
        assertTrue "$s/install.sh: narzędzia asdf przed pakietami cargo/go/cabal (potrzebują toolchainów)" "[ '${tools:-999}' -lt '${lang:-0}' ]"
        assertNotEquals "$s/install.sh: install_sdkman nie woła narzędzi sdkman" "" "$(_line "$s/install.sh" '^[[:space:]]+install_sdkman_tools$')"
        assertNotEquals "$s/install.sh: brak install_sdkman w sekwencji" "" "$sdkman"
    done
}

testUpdatersCallHelpersInOrder() {
    local s asdf tools lang
    for s in $SYSTEMS; do
        asdf="$(_line "$s/update.sh" '^update_asdf$')"
        tools="$(_line "$s/update.sh" '^update_asdf_tools$')"
        lang="$(_line "$s/update.sh" '^update_lang_packages$')"
        assertNotEquals "$s/update.sh: brak update_asdf_tools" "" "$tools"
        assertTrue "$s/update.sh: update_asdf przed update_asdf_tools" "[ '${asdf:-999}' -lt '${tools:-0}' ]"
        assertTrue "$s/update.sh: update_asdf_tools przed update_lang_packages" "[ '${tools:-999}' -lt '${lang:-0}' ]"
        assertNotEquals "$s/update.sh: update_sdkman nie woła narzędzi sdkman" "" "$(_line "$s/update.sh" '^[[:space:]]+update_sdkman_tools$')"
    done
}

testNoHardcodedToolsLeft() {
    local s f
    for s in $SYSTEMS; do
        for f in install.sh update.sh; do
            assertEquals "$s/$f: ręczne sdk install/upgrade" "0" "$(_count "$s/$f" 'sdk (i|install|upgrade) (java|maven|mvnd)')"
            assertEquals "$s/$f: ręczny plugin rust" "0" "$(_count "$s/$f" 'plugin add rust|asdf_bin" (install|global) rust')"
        done
    done
}

testEverySystemSourcesLangPackagesHelpers() {
    local s f
    for s in $SYSTEMS; do
        for f in install.sh update.sh; do
            assertNotEquals "$s/$f: brak source lang_packages_apply.sh" "" "$(_line "$s/$f" 'source .*lang_packages_apply\.sh')"
        done
    done
}

testNoHardcodedLangPackagesLeft() {
    local s f
    for s in $SYSTEMS; do
        for f in install.sh update.sh; do
            assertEquals "$s/$f: ręczny cargo/go/cabal install" "0" "$(_count "$s/$f" 'cargo install|go install|cabal install|(install|update)_difft')"
        done
    done
}

testBuildLibsInEveryLinuxPackageList() {
    local f
    for f in commons/apt_packages.sh redhat/yum_packages.sh; do
        assertNotEquals "$f: brak tablicy build_libs" "" "$(_line "$f" '^build_libs=\(')"
    done
    for f in ubuntu/install.sh ubuntu/update.sh vanilla/install.sh vanilla/update.sh redhat/install.sh redhat/update.sh; do
        assertNotEquals "$f: build_libs poza listą pakietów" "" "$(_line "$f" '"\$\{build_libs\[@\]\}"')"
    done
}

testVanillaKeepsProxyCleanupAroundSdkman() {
    local clear tools
    clear="$(_line vanilla/install.sh 'unset http_proxy')"
    tools="$(_line vanilla/install.sh '^[[:space:]]+install_sdkman_tools$')"
    assertTrue "install: proxy czyszczone przed narzędziami sdkman" "[ '${clear:-999}' -lt '${tools:-0}' ]"
    # w update czyszczenie jest w tej samej podpowłoce co update_sdkman_tools
    assertContains "$(grep -B2 'update_sdkman_tools' "$PROJECT_ROOT/packages/vanilla/update.sh")" "unset http_proxy"
}

testMacInstallsSdkmanToolsEvenWhenSdkmanPresent() {
    assertContains "$(grep -A4 'SDKMAN już zainstalowany' "$PROJECT_ROOT/packages/mac/install.sh")" "install_sdkman_tools"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
