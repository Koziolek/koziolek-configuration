#!/usr/bin/env bash
# Testy jednostkowe: podpięcie completion dla claude-cli (bash/bash_completion.sh)
# oraz klonowania repozytorium z completion (bash/bash_customs.sh).
# bash_completion.sh sourcujemy w izolowanej powłoce z podstawionym HOME/PATH
# (stuby mvn/mvnd — inaczej plik woła `sdk i ...`) i sztucznym $WORKSPACE_TOOLS.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPLETION_SH="$PROJECT_ROOT/bash/bash_completion.sh"
CUSTOMS_SH="$PROJECT_ROOT/bash/bash_customs.sh"
CLAUDE_REPO_URL="https://github.com/cldotdev/claude-bash-completion.git"
CLAUDE_COMP_FILE="claude-completion.bash"

_TMP=''
_TOOLS=''
oneTimeSetUp() {
    _TMP="$(mktemp -d)"
    mkdir -p "$_TMP/bin" "$_TMP/home"
    printf '#!/bin/sh\nexit 0\n' > "$_TMP/bin/mvn"
    cp "$_TMP/bin/mvn" "$_TMP/bin/mvnd"
    chmod +x "$_TMP/bin/mvn" "$_TMP/bin/mvnd"
}
oneTimeTearDown() { rm -rf "$_TMP"; }

setUp() {
    _TOOLS="$(mktemp -d "$_TMP/tools.XXXXXX")"
}

# _source_completion [WORKSPACE_TOOLS] — source bash_completion.sh i wypisz
# rejestrację completion dla `claude` (puste, gdy brak). Kod wyjścia = kod source.
_source_completion() {
    local tools="${1:-$_TOOLS}"
    env -i HOME="$_TMP/home" PATH="$_TMP/bin:/usr/bin:/bin" WORKSPACE_TOOLS="$tools" \
        bash --norc --noprofile -c '. "$1"; rc=$?; complete -p claude 2>/dev/null; exit $rc' _ "$COMPLETION_SH"
}

_make_stub_repo() {
    mkdir -p "$_TOOLS/claude-bash-completion"
    cat > "$_TOOLS/claude-bash-completion/$CLAUDE_COMP_FILE" <<'STUB'
_claude_stub_completion() { COMPREPLY=(); }
complete -o default -F _claude_stub_completion claude
STUB
}

# --- bash_completion.sh ----------------------------------------------------

testRegistersClaudeCompletionWhenRepoPresent() {
    _make_stub_repo
    local out
    out="$(_source_completion)"
    assertContains "completion zarejestrowane z klonu w \$WORKSPACE_TOOLS" "$out" "_claude_stub_completion"
}

testNoClaudeCompletionWhenRepoMissing() {
    local out rc
    out="$(_source_completion)"; rc=$?
    assertEquals "brak klonu nie może wywalić ładowania" 0 "$rc"
    assertEquals "brak rejestracji bez klonu" "" "$out"
}

testNoClaudeCompletionWhenDirExistsButFileMissing() {
    mkdir -p "$_TOOLS/claude-bash-completion"
    assertEquals "" "$(_source_completion)"
}

testLoadsFromWorkspaceToolsNotFromElsewhere() {
    # ten sam plik w innym $WORKSPACE_TOOLS nie może być użyty
    _make_stub_repo
    local other
    other="$(mktemp -d "$_TMP/other.XXXXXX")"
    assertEquals "" "$(_source_completion "$other")"
}

testCompletionSourcedAfterMvndBlock() {
    # claude musi być ostatnim blokiem — jego brak nie może psuć wcześniejszych
    # (mvn/mvnd) i odwrotnie; sprawdzamy kolejność w pliku
    local claude_line mvnd_line
    claude_line=$(grep -n 'claude-bash-completion' "$COMPLETION_SH" | head -1 | cut -d: -f1)
    mvnd_line=$(grep -n 'mvnd-bash-completion' "$COMPLETION_SH" | head -1 | cut -d: -f1)
    assertTrue "blok claude po bloku mvnd" "[ $claude_line -gt $mvnd_line ]"
}

testRealUpstreamCompletionLoadsWhenAvailable() {
    local real="${WORKSPACE_TOOLS:-$HOME/workspace/tools}/claude-bash-completion/$CLAUDE_COMP_FILE"
    # bez klonu upstreamu nic do sprawdzenia (nie startSkipping — pominąłby kolejne testy)
    [ -f "$real" ] || return 0
    mkdir -p "$_TOOLS/claude-bash-completion"
    cp "$real" "$_TOOLS/claude-bash-completion/$CLAUDE_COMP_FILE"
    local out
    out="$(_source_completion)"
    assertContains "prawdziwy skrypt rejestruje completion dla claude" "$out" "_claude_bash_completion"
}

# --- bash_customs.sh -------------------------------------------------------

testCustomsClonesClaudeCompletionRepo() {
    assertTrue "install_lib dla claude-bash-completion" \
        "grep -qF 'install_lib -r \"$CLAUDE_REPO_URL\"' '$CUSTOMS_SH'"
}

testCustomsTargetDirMatchesPathUsedByCompletion() {
    local target
    target=$(grep -F "$CLAUDE_REPO_URL" "$CUSTOMS_SH" | sed -n 's/.*-t "\([^"]*\)".*/\1/p')
    assertEquals "claude-bash-completion" "$target"
    assertTrue "bash_completion.sh czyta z tego samego katalogu" \
        "grep -qF '\$WORKSPACE_TOOLS/$target/$CLAUDE_COMP_FILE' '$COMPLETION_SH'"
}

testCustomsClaudeRepoIsPublicSoNoPrivateFlag() {
    local line
    line=$(grep -F "$CLAUDE_REPO_URL" "$CUSTOMS_SH")
    assertNotContains "publiczne repo nie wymaga -p" "$line" " -p"
}

. "${SHUNIT2:-/opt/shunit2/shunit2}"
