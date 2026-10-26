#!/usr/bin/env bash
# Testy jednostkowe: lista narzędzi sdkman/asdf (packages/commons/sdk_tools.sh)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SDK_TOOLS_FILE="$PROJECT_ROOT/packages/commons/sdk_tools.sh"
TEMPLATES_DIR="$PROJECT_ROOT/bash/templates"

setUp() {
    unset SDKMAN_CANDIDATES ASDF_TOOLS
    # shellcheck source=/dev/null
    . "$SDK_TOOLS_FILE"
}

testSourcingHasNoSideEffects() {
    local out
    out="$(bash -c ". '$SDK_TOOLS_FILE'" 2>&1)"
    assertEquals "sourcowanie nic nie wypisuje" "" "$out"
}

testDefinesBothLists() {
    assertTrue "SDKMAN_CANDIDATES niepusta" "[ ${#SDKMAN_CANDIDATES[@]} -gt 0 ]"
    assertTrue "ASDF_TOOLS niepusta" "[ ${#ASDF_TOOLS[@]} -gt 0 ]"
}

testContainsCurrentTools() {
    local joined=" ${SDKMAN_CANDIDATES[*]} "
    assertContains "$joined" " java "
    assertContains "$joined" " maven "
    assertContains "$joined" " mvnd "
    assertContains "${ASDF_TOOLS[*]}" "rust|"
}

testAsdfListHasOnlyToolchains() {
    local joined="${ASDF_TOOLS[*]}"
    assertContains "$joined" "golang|https://github.com/asdf-community/asdf-golang.git|"
    assertContains "$joined" "ghc|https://github.com/sestrella/asdf-ghcup.git|"
    assertContains "$joined" "cabal|https://github.com/sestrella/asdf-ghcup.git|"
    # narzędzia instaluje lang_packages.sh (go install / cabal install), nie asdf (#172)
    assertNotContains "$joined" "shellcheck"
    assertNotContains "$joined" "shfmt"
}

# _asdf_pos <nazwa> — pozycja narzędzia na liście ASDF_TOOLS (0 = brak)
_asdf_pos() {
    local i=1 e
    for e in "${ASDF_TOOLS[@]}"; do
        [ "${e%%|*}" = "$1" ] && { echo "$i"; return; }
        i=$((i + 1))
    done
    echo 0
}

testAsdfListOrderToolchainsBeforeDependents() {
    # ghc przed cabalem (cabal potrzebuje ghc), rust i golang obecne
    assertTrue "rust na liście" "[ \"$(_asdf_pos rust)\" -gt 0 ]"
    assertTrue "golang na liście" "[ \"$(_asdf_pos golang)\" -gt 0 ]"
    assertTrue "ghc przed cabal" "[ \"$(_asdf_pos ghc)\" -gt 0 ] && [ \"$(_asdf_pos ghc)\" -lt \"$(_asdf_pos cabal)\" ]"
}

testSdkmanCandidatesAreValidAndUnique() {
    local c dups
    for c in "${SDKMAN_CANDIDATES[@]}"; do
        assertTrue "poprawna nazwa '$c'" "[[ '$c' =~ ^[a-z0-9][a-z0-9._-]*$ ]]"
    done
    dups="$(printf '%s\n' "${SDKMAN_CANDIDATES[@]}" | sort | uniq -d)"
    assertEquals "brak duplikatów sdkman" "" "$dups"
}

testAsdfEntriesHaveThreeFieldsWithNameAndVersion() {
    local e name url version extra
    for e in "${ASDF_TOOLS[@]}"; do
        assertEquals "trzy pola w '$e'" 2 "$(grep -o '|' <<< "$e" | wc -l)"
        IFS='|' read -r name url version extra <<< "$e"
        assertNotEquals "nazwa niepusta w '$e'" "" "$name"
        assertNotEquals "wersja niepusta w '$e'" "" "$version"
        assertEquals "brak czwartego pola w '$e'" "" "$extra"
        [ -z "$url" ] || assertTrue "url https w '$e'" "[[ '$url' == https://* ]]"
    done
}

testAsdfNamesUnique() {
    local dups
    dups="$(printf '%s\n' "${ASDF_TOOLS[@]}" | cut -d'|' -f1 | sort | uniq -d)"
    assertEquals "brak duplikatów asdf" "" "$dups"
}

testTemplatesExist() {
    assertTrue ".sdkman.template" "[ -s '$TEMPLATES_DIR/.sdkman.template' ]"
    assertTrue ".tool-versions.template" "[ -s '$TEMPLATES_DIR/.tool-versions.template' ]"
}

testSdkmanTemplateIsCandidateVersionList() {
    local bad dups
    bad="$(grep -vE '^([a-z0-9]+=[^[:space:]=]+|#.*|)$' "$TEMPLATES_DIR/.sdkman.template")"
    assertEquals "linie: kandydat=wersja" "" "$bad"
    dups="$(grep -vE '^(#|$)' "$TEMPLATES_DIR/.sdkman.template" | cut -d= -f1 | sort | uniq -d)"
    assertEquals "brak duplikatów kandydatów" "" "$dups"
}

testSdkmanTemplateCoversSdkmanCandidates() {
    local c
    for c in "${SDKMAN_CANDIDATES[@]}"; do
        assertTrue "'$c' w .sdkman.template" "grep -q '^$c=' '$TEMPLATES_DIR/.sdkman.template'"
    done
}

testToolVersionsTemplateFormat() {
    local bad dups
    bad="$(grep -vE '^([a-z0-9_-]+ [^[:space:]]+( [^[:space:]]+)*|#.*|)$' "$TEMPLATES_DIR/.tool-versions.template")"
    assertEquals "linie: narzędzie wersja…" "" "$bad"
    dups="$(grep -vE '^(#|$)' "$TEMPLATES_DIR/.tool-versions.template" | cut -d' ' -f1 | sort | uniq -d)"
    assertEquals "brak duplikatów narzędzi" "" "$dups"
}

testToolVersionsTemplateHasNoHomeSpecificData() {
    assertFalse "bez ścieżek z \$HOME" "grep -q '/home/' '$TEMPLATES_DIR/.tool-versions.template' '$TEMPLATES_DIR/.sdkman.template'"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
