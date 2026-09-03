#!/usr/bin/env bash
# Testy jednostkowe: bash/contexts/detect.sh
#   detect_context / context_chain / context_is / load_contexts

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/contexts/detect.sh"

_TMP=''
oneTimeSetUp() { _TMP="$(mktemp -d)"; }
oneTimeTearDown() { rm -rf "$_TMP"; }

_mk_os_release() {
    # $1 = ID, $2 = ID_LIKE (opcjonalnie)
    local f="$_TMP/os-release-$RANDOM"
    { printf 'ID=%s\n' "$1"; [ -n "${2:-}" ] && printf 'ID_LIKE=%s\n' "$2"; } > "$f"
    printf '%s' "$f"
}

_detect_with() {
    # _detect_with <uname> <os-release-file>
    OS_RELEASE_FILE="$2" WSL_DISTRO_NAME='' CONFIG_CONTEXT_FORCE='' \
        bash --norc --noprofile -c "
            uname() { echo '$1'; }; export -f uname
            . '$PROJECT_ROOT/bash/contexts/detect.sh'
            detect_context
        "
}

# --- detect_context ---------------------------------------------------------

testDetectsDarwin() {
    assertEquals 'darwin' "$(_detect_with Darwin /nonexistent)"
}

testDetectsVanilla() {
    assertEquals 'vanilla' "$(_detect_with Linux "$(_mk_os_release vanilla debian)")"
}

testDetectsUbuntu() {
    assertEquals 'ubuntu' "$(_detect_with Linux "$(_mk_os_release ubuntu debian)")"
}

testDetectsDebian() {
    assertEquals 'debian' "$(_detect_with Linux "$(_mk_os_release debian)")"
}

testDebianLikeFallsBackToDebian() {
    assertEquals 'debian' "$(_detect_with Linux "$(_mk_os_release linuxmint 'ubuntu debian')")"
}

testDetectsFedora() {
    assertEquals 'redhat' "$(_detect_with Linux "$(_mk_os_release fedora)")"
}

testDetectsCentos() {
    assertEquals 'redhat' "$(_detect_with Linux "$(_mk_os_release centos 'rhel fedora')")"
}

testDetectsRhel() {
    assertEquals 'redhat' "$(_detect_with Linux "$(_mk_os_release rhel fedora)")"
}

testRedhatLikeFallsBackToRedhat() {
    # Oracle Linux — ID nie jest na jawnej liście, tylko ID_LIKE="fedora"
    assertEquals 'redhat' "$(_detect_with Linux "$(_mk_os_release ol fedora)")"
}

testUnknownLinuxFallsBackToLinux() {
    assertEquals 'linux' "$(_detect_with Linux "$(_mk_os_release arch)")"
}

testNoOsReleaseFallsBackToLinux() {
    assertEquals 'linux' "$(_detect_with Linux /nonexistent)"
}

testForceOverridesDetection() {
    local out
    out=$(CONFIG_CONTEXT_FORCE='vanilla' bash --norc --noprofile -c "
        uname() { echo 'Darwin'; }; export -f uname
        . '$PROJECT_ROOT/bash/contexts/detect.sh'
        detect_context
    ")
    assertEquals 'vanilla' "$out"
}

# --- context_chain ---------------------------------------------------------

testChainVanilla() {
    assertEquals 'linux debian vanilla' "$(context_chain vanilla | tr '\n' ' ' | sed 's/ $//')"
}

testChainUbuntu() {
    assertEquals 'linux debian ubuntu' "$(context_chain ubuntu | tr '\n' ' ' | sed 's/ $//')"
}

testChainDarwin() {
    assertEquals 'darwin' "$(context_chain darwin | tr '\n' ' ' | sed 's/ $//')"
}

testChainWsl() {
    assertEquals 'linux debian wsl' "$(context_chain wsl | tr '\n' ' ' | sed 's/ $//')"
}

testChainRedhat() {
    assertEquals 'linux redhat' "$(context_chain redhat | tr '\n' ' ' | sed 's/ $//')"
}

testChainUnknownFallsBackToLinux() {
    assertEquals 'linux' "$(context_chain nonsense | tr '\n' ' ' | sed 's/ $//')"
}

# --- context_is -----------------------------------------------------------

testContextIsDebianTrueForVanilla() {
    CONFIG_CONTEXT='vanilla' context_is debian
    assertEquals 'context_is debian musi być prawdą dla vanilla' 0 $?
}

testContextIsDebianTrueForUbuntu() {
    CONFIG_CONTEXT='ubuntu' context_is debian
    assertEquals 'context_is debian musi być prawdą dla ubuntu' 0 $?
}

testContextIsDebianFalseForDarwin() {
    CONFIG_CONTEXT='darwin' context_is debian
    assertNotEquals 'context_is debian musi być fałszem dla darwin' 0 $?
}

testContextIsLeafMatches() {
    CONFIG_CONTEXT='vanilla' context_is vanilla
    assertEquals 'context_is vanilla musi być prawdą dla vanilla' 0 $?
}

testContextIsRedhatFalseForDebianFamily() {
    CONFIG_CONTEXT='ubuntu' context_is redhat
    assertNotEquals 'context_is redhat musi być fałszem dla ubuntu' 0 $?
}

# --- load_contexts (sourcing łańcucha) ----------------------------------

testLoadContextsSourcesChainInOrder() {
    # fałszywy CONTEXTS_DIR z plikami dopisującymi do zmiennej
    local d="$_TMP/ctx-$RANDOM"
    mkdir -p "$d"
    echo 'ORDER="${ORDER}linux;"'  > "$d/linux.sh"
    echo 'ORDER="${ORDER}debian;"' > "$d/debian.sh"
    echo 'ORDER="${ORDER}vanilla;"'> "$d/vanilla.sh"
    local out
    out=$(CONFIG_CONTEXT='vanilla' CONTEXTS_DIR="$d" bash --norc --noprofile -c "
        source_if_exists() { [ -f \"\$2/\$1.sh\" ] && . \"\$2/\$1.sh\"; }
        . '$PROJECT_ROOT/bash/contexts/detect.sh'
        ORDER=''
        load_contexts
        printf '%s' \"\$ORDER\"
    ")
    assertEquals 'linux;debian;vanilla;' "$out"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
