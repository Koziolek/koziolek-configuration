#!/usr/bin/env bash
# Testy jednostkowe: bash/functions.d/096_function_apt_trust.sh (refresh_apt_gpg_keys).
# `gpg`, `sudo` i `apt-get` są mockami (funkcjami) — nic nie dotyka prawdziwego apt ani keyringu.
# Wykrywanie wygasłych kluczy: `gpg --with-colons`, pole 2 rekordu pub = `e` (nie ludzki `[expired: data]`).

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export MESSAGES_LANG=pl
export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/096_function_apt_trust.sh"

setUp() {
    _TMP="$(mktemp -d)"
    KEYRING_DIR="$_TMP/keyrings"
    mkdir -p "$KEYRING_DIR"

    sudo() { "$@"; }
    apt-get() { return 0; }
    # Zachowanie jak prawdziwy gpg: `--with-colons` daje rekordy maszynowe, bez niego ludzki zapis.
    # Plik `*-expired.gpg` to klucz po terminie, `*-valid.gpg` ważny.
    gpg() {
        local colons=0 f
        for f in "$@"; do [ "$f" = --with-colons ] && colons=1; done
        f="${*: -1}"
        if [ "$colons" = 1 ]; then
            case "$f" in
            *-expired.gpg) echo "pub:e:255:22:AAAA:1500000000:1600000000::-:::sc::::::23::0:" ;;
            *) echo "pub:-:255:22:BBBB:1500000000:::-:::scESC::::::23::0:" ;;
            esac
        else
            case "$f" in
            *-expired.gpg) echo "pub   rsa4096 2017-07-14 [SC] [expired: 2020-09-13]" ;;
            *) echo "pub   rsa4096 2017-07-14 [SC]" ;;
            esac
        fi
    }
}

tearDown() {
    rm -rf "$_TMP"
    unset -f sudo apt-get gpg
}

testExpiredImportedKeyIsRemoved() {
    : >"$KEYRING_DIR/imported-old-expired.gpg"
    : >"$KEYRING_DIR/imported-new-valid.gpg"
    refresh_apt_gpg_keys >/dev/null 2>&1
    assertFalse "wygasły klucz usunięty" "[ -e '$KEYRING_DIR/imported-old-expired.gpg' ]"
    assertTrue "ważny klucz zostaje" "[ -e '$KEYRING_DIR/imported-new-valid.gpg' ]"
}

testNoExpiredKeysLeavesKeyring() {
    : >"$KEYRING_DIR/imported-new-valid.gpg"
    refresh_apt_gpg_keys >/dev/null 2>&1
    assertTrue "klucz zostaje" "[ -e '$KEYRING_DIR/imported-new-valid.gpg' ]"
}

testExpiredKeyIsReportedAsRemoved() {
    : >"$KEYRING_DIR/imported-old-expired.gpg"
    local out
    out="$(refresh_apt_gpg_keys 2>&1)"
    assertContains "komunikat o usunięciu" "$out" "imported-old-expired.gpg"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
