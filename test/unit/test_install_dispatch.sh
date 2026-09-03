#!/usr/bin/env bash
# Testy jednostkowe: install.sh — wybór skryptu instalacyjnego per system.
# Używa INSTALL_DISPATCH_DRY_RUN=1 (install.sh wypisuje wybrany skrypt i wychodzi
# przed klonem repo) oraz CONFIG_CONTEXT_FORCE (bez sięgania po sieć).

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_SH="$PROJECT_ROOT/install.sh"

_TMP=''
oneTimeSetUp() { _TMP="$(mktemp -d)"; }
oneTimeTearDown() { rm -rf "$_TMP"; }

_dispatch() {
    # _dispatch <ctx> [extra env assignments...] ; echo -> stdout, kod -> $?
    local ctx="$1"; shift
    env INSTALL_DISPATCH_DRY_RUN=1 CONFIG_CONTEXT_FORCE="$ctx" \
        CONTAINERENV_FILE=/nonexistent HOST_OS_RELEASE_FILE=/nonexistent \
        "$@" bash "$INSTALL_SH" 2>/dev/null | tail -1
}

testDarwinPicksMacScript() {
    assertEquals 'initial_packages_mac.sh' "$(_dispatch darwin)"
}

testUbuntuPicksLinuxScript() {
    assertEquals 'initial_packages_ubuntu.sh' "$(_dispatch ubuntu)"
}

testDebianPicksLinuxScript() {
    assertEquals 'initial_packages_ubuntu.sh' "$(_dispatch debian)"
}

testWslPicksLinuxScript() {
    assertEquals 'initial_packages_ubuntu.sh' "$(_dispatch wsl)"
}

testRedhatPicksRedhatScript() {
    assertEquals 'initial_packages_redhat.sh' "$(_dispatch redhat)"
}

testVanillaSubsystemPicksVanillaScript() {
    # marker kontenera + /run/host/etc/os-release z ID=vanilla → subsystem apx
    local host_os="$_TMP/host-os-release"
    printf 'ID=debian\nID_LIKE=vanilla\n' > "$host_os"
    local containerenv="$_TMP/containerenv"; : > "$containerenv"
    local out
    out=$(env INSTALL_DISPATCH_DRY_RUN=1 CONFIG_CONTEXT_FORCE=debian \
        CONTAINERENV_FILE="$containerenv" HOST_OS_RELEASE_FILE="$host_os" \
        bash "$INSTALL_SH" 2>/dev/null | tail -1)
    assertEquals 'initial_packages_vanilla.sh' "$out"
}

testVanillaHostAborts() {
    # ctx=vanilla, brak markera kontenera → immutable host → kod != 0
    local rc=0
    env INSTALL_DISPATCH_DRY_RUN=1 CONFIG_CONTEXT_FORCE=vanilla \
        CONTAINERENV_FILE=/nonexistent HOST_OS_RELEASE_FILE=/nonexistent \
        bash "$INSTALL_SH" >/dev/null 2>&1 || rc=$?
    assertNotEquals 0 "$rc"
}

testUnsupportedSystemAborts() {
    local rc=0
    env INSTALL_DISPATCH_DRY_RUN=1 CONFIG_CONTEXT_FORCE=linux \
        CONTAINERENV_FILE=/nonexistent HOST_OS_RELEASE_FILE=/nonexistent \
        bash "$INSTALL_SH" >/dev/null 2>&1 || rc=$?
    assertNotEquals 0 "$rc"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
