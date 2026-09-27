#!/usr/bin/env bash
# Testy jednostkowe: services/services_functions.sh
# Zakres: update_sdkman_jdk_certs (import certyfikatu nginx do cacerts JDK zarządzanych sdkman)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/services/services_functions.sh"

_TEST_DIR=''
_ORIG_PATH=''

setUp() {
    _TEST_DIR="$(mktemp -d)"
    _ORIG_PATH="$PATH"

    export NGINX_DATA="$_TEST_DIR/nginx"
    export SDKMAN_DIR="$_TEST_DIR/sdkman"
    mkdir -p "$NGINX_DATA/ssl"

    KEYTOOL_LOG="$_TEST_DIR/keytool.log"
    export KEYTOOL_LOG
    unset KEYTOOL_FAIL_IMPORT

    mkdir -p "$_TEST_DIR/bin"
    cat > "$_TEST_DIR/bin/keytool" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$KEYTOOL_LOG"
for a in "$@"; do
  [ "$a" = "-delete" ] && exit 1
done
[ -n "$KEYTOOL_FAIL_IMPORT" ] && exit 1
exit 0
EOF
    chmod +x "$_TEST_DIR/bin/keytool"
    export PATH="$_TEST_DIR/bin:$PATH"
}

tearDown() {
    export PATH="$_ORIG_PATH"
    rm -rf "$_TEST_DIR"
}

_make_cert() {
    printf 'fake-cert' > "$NGINX_DATA/ssl/nginx.crt"
}

_make_jdk() {
    # $1 = nazwa katalogu JDK
    mkdir -p "$SDKMAN_DIR/candidates/java/$1/lib/security"
    printf 'fake-cacerts' > "$SDKMAN_DIR/candidates/java/$1/lib/security/cacerts"
}

# ---------------------------------------------------------------------------

testMissingCertFileFails() {
    mkdir -p "$SDKMAN_DIR/candidates/java"
    local out
    out="$(update_sdkman_jdk_certs)"
    local rc=$?
    assertEquals 1 "$rc"
    assertContains "$out" "WARN"
}

testMissingSdkmanDirFails() {
    _make_cert
    local out
    out="$(update_sdkman_jdk_certs)"
    local rc=$?
    assertEquals 1 "$rc"
    assertContains "$out" "WARN"
}

testImportsCertToEachJdk() {
    _make_cert
    _make_jdk "17.0.9-tem"
    _make_jdk "21.0.1-tem"
    ln -s "17.0.9-tem" "$SDKMAN_DIR/candidates/java/current"

    update_sdkman_jdk_certs > /dev/null

    local calls
    calls="$(grep -c -- '-importcert' "$KEYTOOL_LOG")"
    assertEquals 2 "$calls"
    assertFalse "symlink 'current' nie powinien być przetwarzany" \
        "grep -q 'candidates/java/current/' '$KEYTOOL_LOG'"
}

testSkipsJdkWithoutCacerts() {
    _make_cert
    mkdir -p "$SDKMAN_DIR/candidates/java/broken-jdk"

    local out
    out="$(update_sdkman_jdk_certs)"

    assertContains "$out" "WARN"
    assertFalse "keytool nie powinien być wołany dla JDK bez cacerts" \
        "[ -f '$KEYTOOL_LOG' ]"
}

testLogsErrorWhenImportFails() {
    _make_cert
    _make_jdk "17.0.9-tem"
    export KEYTOOL_FAIL_IMPORT=1

    local out
    out="$(update_sdkman_jdk_certs)"

    assertContains "$out" "ERROR"
}

# shellcheck source=/dev/null
. "$(command -v shunit2 || echo /usr/bin/shunit2)"
