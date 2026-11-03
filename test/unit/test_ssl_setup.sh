#!/usr/bin/env bash
# Testy jednostkowe: services/nginx/ssl/ssl_setup.sh (prepare_cert) - cytowanie ścieżek i idempotencja (#199).
# `openssl` jest atrapą w PATH (bez prawdziwego certyfikatu); prawdziwy openssl: --e2e-certs.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export MESSAGES_LANG=pl
export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/005_function_messages.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/020_function_process.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/services/nginx/ssl/ssl_setup.sh"

setUp() {
    _T="$(mktemp -d)"
    _ORIG_PATH="$PATH"
    mkdir -p "$_T/bin"
    export OPENSSL_LOG="$_T/openssl.log"
    : >"$OPENSSL_LOG"
    # atrapa sudo: uruchamia polecenie wprost (bez roota)
    cat >"$_T/bin/sudo" <<'S'
#!/usr/bin/env bash
[[ "$1" == "-K" ]] && exit 0
exec "$@"
S
    cat >"$_T/bin/openssl" <<'S'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OPENSSL_LOG"
case "$1" in
    x509) exit "${OPENSSL_CHECKEND_RC:-0}" ;;
    req)
        while [[ $# -gt 0 ]]; do
            case "$1" in -keyout) echo key >"$2" ;; -out) echo crt >"$2" ;; esac
            shift
        done
        exit "${OPENSSL_REQ_RC:-0}"
        ;;
esac
S
    chmod +x "$_T/bin/sudo" "$_T/bin/openssl"
    PATH="$_T/bin:$PATH"
    unset OPENSSL_CHECKEND_RC OPENSSL_REQ_RC PREPARE_CERT_FORCE PREPARE_CERT_MIN_DAYS
    export NGINX_DATA="$_T/with space/nginx"
    _SUDO_DEPTH=0
}

tearDown() {
    PATH="$_ORIG_PATH"
    rm -rf "$_T"
}

_pair() {
    mkdir -p "$NGINX_DATA/ssl"
    echo OLDCRT >"$NGINX_DATA/ssl/nginx.crt"
    echo OLDKEY >"$NGINX_DATA/ssl/nginx.key"
}

_req_calls() { grep -c '^req ' "$OPENSSL_LOG"; }

_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

testGeneratesWhenNoPairAndHandlesSpaceInPath() {
    prepare_cert >/dev/null
    assertEquals "openssl req raz" 1 "$(_req_calls)"
    assertEquals crt "$(cat "$NGINX_DATA/ssl/nginx.crt")"
    assertEquals key "$(cat "$NGINX_DATA/ssl/nginx.key")"
    assertEquals "uprawnienia klucza" 600 "$(_mode "$NGINX_DATA/ssl/nginx.key")"
    assertEquals "uprawnienia certu" 644 "$(_mode "$NGINX_DATA/ssl/nginx.crt")"
}

testValidPairIsNotRegenerated() {
    _pair
    local out
    out="$(prepare_cert)"
    assertEquals "brak openssl req" 0 "$(_req_calls)"
    assertEquals OLDCRT "$(cat "$NGINX_DATA/ssl/nginx.crt")"
    assertEquals OLDKEY "$(cat "$NGINX_DATA/ssl/nginx.key")"
    assertContains "$out" "pomijam generowanie"
    assertNotContains "bez next_steps" "$out" "Następne kroki"
}

testRepeatedCallsKeepCertificate() {
    prepare_cert >/dev/null
    prepare_cert >/dev/null
    prepare_cert >/dev/null
    assertEquals "generowane tylko raz" 1 "$(_req_calls)"
}

testExpiringCertIsRegenerated() {
    _pair
    export OPENSSL_CHECKEND_RC=1
    prepare_cert >/dev/null
    assertEquals 1 "$(_req_calls)"
    assertEquals crt "$(cat "$NGINX_DATA/ssl/nginx.crt")"
}

testCheckendUsesMinDays() {
    _pair
    PREPARE_CERT_MIN_DAYS=10 prepare_cert >/dev/null
    assertContains "$(cat "$OPENSSL_LOG")" "-checkend 864000"
}

testMissingKeyRegenerates() {
    _pair
    rm "$NGINX_DATA/ssl/nginx.key"
    prepare_cert >/dev/null
    assertEquals 1 "$(_req_calls)"
}

testForceFlagRegenerates() {
    _pair
    prepare_cert --force >/dev/null
    assertEquals 1 "$(_req_calls)"
    assertEquals crt "$(cat "$NGINX_DATA/ssl/nginx.crt")"
}

testForceEnvRegenerates() {
    _pair
    PREPARE_CERT_FORCE=1 prepare_cert >/dev/null
    assertEquals 1 "$(_req_calls)"
}

testOpensslFailureReturnsNonZeroAndBalancesSudo() {
    export OPENSSL_REQ_RC=1
    prepare_cert >/dev/null
    assertEquals 1 $?
    assertEquals "licznik sudo wyzerowany" 0 "${_SUDO_DEPTH:-0}"
}

testNoUnquotedPathVariablesInSslSetup() {
    local bad
    bad="$(grep -nE '\$\{?(NGINX_DATA|ssl_dir|crt|key)\}?' "$PROJECT_ROOT/services/nginx/ssl/ssl_setup.sh" |
        grep -vE '^[0-9]+:\s*#' | grep -vE '"[^"]*\$\{?(NGINX_DATA|ssl_dir|crt|key)\}?[^"]*"' || true)"
    assertEquals "niecytowane zmienne ścieżkowe: $bad" "" "$bad"
}

testShellcheckSc2086CleanForPrepareCert() {
    command -v shellcheck >/dev/null || startSkipping
    shellcheck -s bash -i SC2086 "$PROJECT_ROOT/services/nginx/ssl/ssl_setup.sh" >/dev/null
    assertEquals 0 $?
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
