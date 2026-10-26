#!/usr/bin/env bash
# Testy jednostkowe: install/update narzędzi z listy sdkman/asdf (packages/commons/sdk_tools_apply.sh).
# `sdk` to mock w fałszywym sdkman-init.sh, `asdf` — skrypt w $_TMP; oba logują wywołania.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

setUp() {
    _TMP="$(mktemp -d)"
    _LOG="$_TMP/calls.log"
    : > "$_LOG"
    export SDKMAN_DIR="$_TMP/sdkman"
    mkdir -p "$SDKMAN_DIR/bin" "$SDKMAN_DIR/candidates"
    export ASDF_BIN="$_TMP/asdf"
    export ASDF_PLUGINS_FILE="$_TMP/plugins"
    : > "$ASDF_PLUGINS_FILE"
    unset SDK_FAIL ASDF_FAIL ASDF_NO_SET
    # shellcheck source=/dev/null
    . "$PROJECT_ROOT/packages/commons/sdk_tools_apply.sh"
    SDKMAN_CANDIDATES=(java maven mvnd)
    ASDF_TOOLS=("rust|https://example.invalid/asdf-rust.git|latest")
}

tearDown() {
    rm -rf "$_TMP"
}

# Mock SDKMAN-a: `sdk` sięga po niepodane $3 (jak sdkman-install.sh) — pod `set -u` wywaliłoby się od razu.
_mock_sdkman() {
    cat > "$SDKMAN_DIR/bin/sdkman-init.sh" <<MOCK
sdk() {
    echo "sdk \$1 \${2:-}" >> "$_LOG"
    : "\$3"
    case " \${SDK_FAIL:-} " in *" \$2 "*) return 1;; esac
    return 0
}
MOCK
}

_mock_asdf() {
    cat > "$ASDF_BIN" <<MOCK
#!/usr/bin/env bash
echo "asdf \$*" >> "$_LOG"
case "\$1 \$2" in
    "plugin list") cat "$ASDF_PLUGINS_FILE"; exit 0;;
    "plugin add") echo "\$3" >> "$ASDF_PLUGINS_FILE";;
esac
if [ "\$1" = help ]; then
    [ -n "\${ASDF_NO_SET:-}" ] && echo "asdf global <name> <version>" || printf 'asdf set [-u] <name> <versions...>\n'
    exit 0
fi
case " \${ASDF_FAIL:-} " in *" \$2 "*|*" \$3 "*) exit 1;; esac
exit 0
MOCK
    chmod +x "$ASDF_BIN"
}

_calls() { cat "$_LOG"; }

# ---------------------------------------------------------------- sdkman

testSdkmanInstallsEveryCandidateInOrder() {
    _mock_sdkman
    install_sdkman_tools >/dev/null
    assertEquals "sdk install x3" "sdk install java
sdk install maven
sdk install mvnd" "$(_calls)"
}

testSdkmanNewListEntryIsPickedUp() {
    _mock_sdkman
    SDKMAN_CANDIDATES+=(quarkus)
    install_sdkman_tools >/dev/null
    assertContains "$(_calls)" "sdk install quarkus"
}

testSdkmanFailureOfOneDoesNotStopOthers() {
    _mock_sdkman
    SDK_FAIL="maven"
    local out rc
    out="$(install_sdkman_tools)"; rc=$?
    assertEquals 0 "$rc"
    assertContains "$(_calls)" "sdk install mvnd"
    assertContains "$out" "nie udało się: maven"
}

testSdkmanMissingIsWarningNotError() {
    local out rc
    out="$(install_sdkman_tools)"; rc=$?
    assertEquals 0 "$rc"
    assertContains "$out" "SDKMAN nie zainstalowany"
    assertEquals "" "$(_calls)"
}

testSdkmanWorksUnderStrictModeOfCaller() {
    _mock_sdkman
    local out
    out="$(bash -c "set -Eeuo pipefail; trap 'echo ERRTRAP' ERR
        export SDKMAN_DIR='$SDKMAN_DIR'
        . '$PROJECT_ROOT/packages/commons/sdk_tools_apply.sh'
        SDK_FAIL=java install_sdkman_tools; echo AFTER" 2>&1)"
    assertContains "dalej po błędzie narzędzia" "$out" "AFTER"
    assertNotContains "trap ERR wołającego nie strzela" "$out" "ERRTRAP"
    assertContains "$(_calls)" "sdk install mvnd"
}

testSdkmanUpdateUpgradesInstalledAndInstallsMissing() {
    _mock_sdkman
    mkdir -p "$SDKMAN_DIR/candidates/java" "$SDKMAN_DIR/candidates/maven"
    update_sdkman_tools >/dev/null
    assertEquals "upgrade dla zainstalowanych, install dla brakującego" "sdk upgrade java
sdk upgrade maven
sdk install mvnd" "$(_calls)"
}

testSdkmanUpdateUpgradeFailureIsNotReported() {
    _mock_sdkman
    mkdir -p "$SDKMAN_DIR/candidates/java"
    SDK_FAIL="java"
    local out
    out="$(update_sdkman_tools)"
    assertNotContains "$out" "nie udało się"
}

testSdkmanInstallIsIdempotentCallPattern() {
    _mock_sdkman
    install_sdkman_tools >/dev/null
    install_sdkman_tools >/dev/null
    assertEquals 6 "$(wc -l < "$_LOG")"
}

# ---------------------------------------------------------------- asdf

testAsdfInstallOrder() {
    _mock_asdf
    install_asdf_tools >/dev/null
    assertEquals "plugin list → add → install → set → reshim" "asdf plugin list
asdf plugin add rust https://example.invalid/asdf-rust.git
asdf install rust latest
asdf help
asdf set -u rust latest
asdf reshim" "$(_calls)"
}

testAsdfFallsBackToGlobalForOldAsdf() {
    _mock_asdf
    ASDF_NO_SET=1
    export ASDF_NO_SET
    install_asdf_tools >/dev/null
    assertContains "$(_calls)" "asdf global rust latest"
    assertNotContains "$(_calls)" "asdf set"
}

testAsdfPluginAddedOnlyOnce() {
    _mock_asdf
    install_asdf_tools >/dev/null
    : > "$_LOG"
    install_asdf_tools >/dev/null
    assertNotContains "drugie uruchomienie nie dodaje pluginu" "$(_calls)" "plugin add"
    assertContains "$(_calls)" "asdf install rust latest"
}

testAsdfUpdateRefreshesPlugin() {
    _mock_asdf
    echo rust > "$ASDF_PLUGINS_FILE"
    update_asdf_tools >/dev/null
    assertContains "$(_calls)" "asdf plugin update rust"
    assertContains "$(_calls)" "asdf install rust latest"
}

testAsdfInstallDoesNotUpdatePlugin() {
    _mock_asdf
    echo rust > "$ASDF_PLUGINS_FILE"
    install_asdf_tools >/dev/null
    assertNotContains "$(_calls)" "plugin update"
}

testAsdfPluginWithoutUrlUsesRegistry() {
    _mock_asdf
    ASDF_TOOLS=("golang||1.22.0")
    install_asdf_tools >/dev/null
    assertContains "$(_calls)" "asdf plugin add golang"
    assertContains "$(_calls)" "asdf install golang 1.22.0"
}

testAsdfNewListEntryIsPickedUp() {
    _mock_asdf
    ASDF_TOOLS+=("shfmt||latest")
    install_asdf_tools >/dev/null
    assertContains "$(_calls)" "asdf install shfmt latest"
}

testAsdfFailureOfOneDoesNotStopOthers() {
    _mock_asdf
    ASDF_TOOLS=("rust|https://example.invalid/r.git|latest" "shfmt||latest")
    export ASDF_FAIL="rust"
    local out rc
    out="$(install_asdf_tools)"; rc=$?
    assertEquals 0 "$rc"
    assertContains "$(_calls)" "asdf install shfmt latest"
    assertContains "$out" "nie udało się: rust"
}

testAsdfInvalidEntryIsReportedAndSkipped() {
    _mock_asdf
    ASDF_TOOLS=("brak-wersji|" "shfmt||latest")
    local out
    out="$(install_asdf_tools)"
    assertContains "$out" "Niepoprawny wpis ASDF_TOOLS"
    assertContains "$(_calls)" "asdf install shfmt latest"
}

testAsdfMissingIsWarningNotError() {
    local out rc
    out="$(install_asdf_tools)"; rc=$?
    assertEquals 0 "$rc"
    assertContains "$out" "asdf nie zainstalowany"
}

testAsdfWorksUnderStrictModeOfCaller() {
    _mock_asdf
    local out
    out="$(bash -c "set -Eeuo pipefail; trap 'echo ERRTRAP' ERR
        export ASDF_BIN='$ASDF_BIN'
        . '$PROJECT_ROOT/packages/commons/sdk_tools_apply.sh'
        ASDF_FAIL=rust install_asdf_tools; echo AFTER" 2>&1)"
    assertContains "$out" "AFTER"
    assertNotContains "$out" "ERRTRAP"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
