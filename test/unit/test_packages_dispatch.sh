#!/usr/bin/env bash
# Testy jednostkowe: initial_packages.sh / update_packages.sh (root) — dispatcher
# lokalny (już sklonowane repo), wybór packages/<initial|update>_packages_<ctx>.sh.
# Mirror test_install_dispatch.sh, ale bez sieci w ogóle (żadnego fetchowania —
# oba skrypty sourcują lokalny bash/contexts/detect.sh).
# Używa PACKAGES_DISPATCH_DRY_RUN=1 i CONFIG_CONTEXT_FORCE.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INITIAL_SH="$PROJECT_ROOT/initial_packages.sh"
UPDATE_SH="$PROJECT_ROOT/update_packages.sh"

_TMP=''
oneTimeSetUp() { _TMP="$(mktemp -d)"; }
oneTimeTearDown() { rm -rf "$_TMP"; }

_dispatch() {
    # _dispatch <skrypt> <ctx> ; echo -> stdout, kod -> $?
    local script="$1" ctx="$2"
    env PACKAGES_DISPATCH_DRY_RUN=1 CONFIG_CONTEXT_FORCE="$ctx" \
        CONTAINERENV_FILE=/nonexistent HOST_OS_RELEASE_FILE=/nonexistent \
        bash "$script" 2>/dev/null | tail -1
}

# --- initial_packages.sh ---------------------------------------------------

testInitialDarwinPicksMacScript() {
    assertEquals 'packages/initial_packages_mac.sh' "$(_dispatch "$INITIAL_SH" darwin)"
}

testInitialUbuntuPicksUbuntuScript() {
    assertEquals 'packages/initial_packages_ubuntu.sh' "$(_dispatch "$INITIAL_SH" ubuntu)"
}

testInitialDebianPicksUbuntuScript() {
    assertEquals 'packages/initial_packages_ubuntu.sh' "$(_dispatch "$INITIAL_SH" debian)"
}

testInitialWslPicksUbuntuScript() {
    assertEquals 'packages/initial_packages_ubuntu.sh' "$(_dispatch "$INITIAL_SH" wsl)"
}

testInitialRedhatPicksRedhatScript() {
    assertEquals 'packages/initial_packages_redhat.sh' "$(_dispatch "$INITIAL_SH" redhat)"
}

testInitialVanillaSubsystemPicksVanillaScript() {
    local host_os="$_TMP/host-os-release"
    printf 'ID=debian\nID_LIKE=vanilla\n' > "$host_os"
    local containerenv="$_TMP/containerenv"; : > "$containerenv"
    local out
    out=$(env PACKAGES_DISPATCH_DRY_RUN=1 CONFIG_CONTEXT_FORCE=debian \
        CONTAINERENV_FILE="$containerenv" HOST_OS_RELEASE_FILE="$host_os" \
        bash "$INITIAL_SH" 2>/dev/null | tail -1)
    assertEquals 'packages/initial_packages_vanilla.sh' "$out"
}

testInitialVanillaHostAborts() {
    local rc=0
    env PACKAGES_DISPATCH_DRY_RUN=1 CONFIG_CONTEXT_FORCE=vanilla \
        CONTAINERENV_FILE=/nonexistent HOST_OS_RELEASE_FILE=/nonexistent \
        bash "$INITIAL_SH" >/dev/null 2>&1 || rc=$?
    assertNotEquals 0 "$rc"
}

testInitialUnsupportedSystemAborts() {
    local rc=0
    env PACKAGES_DISPATCH_DRY_RUN=1 CONFIG_CONTEXT_FORCE=linux \
        CONTAINERENV_FILE=/nonexistent HOST_OS_RELEASE_FILE=/nonexistent \
        bash "$INITIAL_SH" >/dev/null 2>&1 || rc=$?
    assertNotEquals 0 "$rc"
}

# --- update_packages.sh -----------------------------------------------------

testUpdateUbuntuPicksUbuntuScript() {
    assertEquals 'packages/update_packages_ubuntu.sh' "$(_dispatch "$UPDATE_SH" ubuntu)"
}

testUpdateRedhatPicksRedhatScript() {
    assertEquals 'packages/update_packages_redhat.sh' "$(_dispatch "$UPDATE_SH" redhat)"
}

testUpdateDarwinPicksMacScript() {
    assertEquals 'packages/update_packages_mac.sh' "$(_dispatch "$UPDATE_SH" darwin)"
}

testUpdateVanillaHostAborts() {
    local rc=0
    env PACKAGES_DISPATCH_DRY_RUN=1 CONFIG_CONTEXT_FORCE=vanilla \
        CONTAINERENV_FILE=/nonexistent HOST_OS_RELEASE_FILE=/nonexistent \
        bash "$UPDATE_SH" >/dev/null 2>&1 || rc=$?
    assertNotEquals 0 "$rc"
}

testUpdateUnsupportedSystemAborts() {
    local rc=0
    env PACKAGES_DISPATCH_DRY_RUN=1 CONFIG_CONTEXT_FORCE=linux \
        CONTAINERENV_FILE=/nonexistent HOST_OS_RELEASE_FILE=/nonexistent \
        bash "$UPDATE_SH" >/dev/null 2>&1 || rc=$?
    assertNotEquals 0 "$rc"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
