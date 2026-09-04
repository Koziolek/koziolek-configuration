#!/usr/bin/env bash
# Testy jednostkowe: bash/functions.d/140_function_diagnostic.sh (hwinfo + run_diagnostic).
# hwinfo: mockuje dmidecode/lspci (fixture zbliżona do prawdziwego formatu) — łapie regresje
# we wzorcach awk/sed (złe nazwy pól = cicho pusty output). /proc/cpuinfo i /proc/meminfo
# NIE są mockowane — kontener testowy jest Linuksem, realne /proc wystarcza do testu
# ścieżki parsowania.
# run_diagnostic: mockuje $WORKSPACE_TOOLS/fix-comp/pre-analyze.sh (fix-comp to osobne,
# prywatne repo — tu tylko sprawdzamy, że run_diagnostic poprawnie je lokalizuje/woła).

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

_BIN=''
oneTimeSetUp() {
    _BIN="$(mktemp -d)"

    cat > "$_BIN/dmidecode" <<'MOCK'
#!/bin/sh
case "$2" in
  processor)
    cat <<'EOF'
Handle 0x0001, DMI type 4, 42 bytes
Processor Information
	Socket Designation: CPU0
	Family: Zen 3
	Manufacturer: AuthenticAMD
	Version: AMD Ryzen 9 5950X
	Max Speed: 3400 MHz
	Core Count: 16
	Thread Count: 32
EOF
    ;;
  baseboard)
    cat <<'EOF'
Handle 0x0002, DMI type 2, 15 bytes
Base Board Information
	Manufacturer: ASUSTeK COMPUTER INC.
	Product Name: TRX40-PRO S
	Version: Rev 1.xx
	Serial Number: 123456789
	Asset Tag: Default string
EOF
    ;;
  bios)
    cat <<'EOF'
Handle 0x0000, DMI type 0, 26 bytes
BIOS Information
	Vendor: American Megatrends Inc.
	Version: 1401
	Release Date: 03/15/2023
	Firmware Revision: 5.19
EOF
    ;;
  memory)
    cat <<'EOF'
Handle 0x0010, DMI type 17, 92 bytes
Memory Device
	Size: 32 GB
	Locator: DIMM_A1
	Type: DDR4
	Speed: 3200 MT/s
	Manufacturer: Corsair
	Part Number: CMK64GX4M4
	Form Factor: DIMM
Handle 0x0011, DMI type 17, 92 bytes
Memory Device
	Size: No Module Installed
	Locator: DIMM_A2
EOF
    ;;
  display)
    echo "  Manufacturer: NVIDIA"
    ;;
esac
MOCK
    chmod +x "$_BIN/dmidecode"

    cat > "$_BIN/lspci" <<'MOCK'
#!/bin/sh
echo "01:00.0 VGA compatible controller: NVIDIA Corporation Device 2684"
echo "00:02.0 Ethernet controller: Intel Corporation Device 15f3"
MOCK
    chmod +x "$_BIN/lspci"
}
oneTimeTearDown() { rm -rf "$_BIN"; }

_run() {
    # _run <fn-wywolanie...>; PATH z mockami z przodu, funkcje z pliku źródłowego
    PATH="$_BIN:$PATH" bash --norc --noprofile -c "
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh'
        . '$PROJECT_ROOT/bash/functions.d/140_function_diagnostic.sh'
        $*
    "
}

# --- _hwinfo_check_deps ------------------------------------------------------

testCheckDepsFailsWhenDmidecodeMissing() {
    # kontener testowy nie ma dmidecode/lspci zainstalowanych — bez $_BIN w PATH
    # to dokładnie ścieżka "brakujące zależności".
    local out rc=0
    out=$(bash --norc --noprofile -c "
            . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh'
            . '$PROJECT_ROOT/bash/functions.d/140_function_diagnostic.sh'
            _hwinfo_check_deps
        " 2>&1) || rc=$?
    assertNotEquals 'brak dmidecode w PATH musi dać błąd' 0 "$rc"
    assertContains "$out" 'brakujące zależności'
}

testCheckDepsOkWhenPresentAndRoot() {
    # kontener testowy działa jako root — sprawdzamy tylko ścieżkę "wszystko jest"
    if [ "$EUID" -ne 0 ]; then
        startSkipping
        return
    fi
    local rc=0
    _run '_hwinfo_check_deps' || rc=$?
    assertEquals 0 "$rc"
}

# --- hwinfo_cpu / hwinfo_motherboard / hwinfo_ram / hwinfo_gpu --------------

testCpuIncludesDmidecodeFields() {
    local out
    out=$(_run 'hwinfo_cpu')
    assertContains "$out" 'AMD Ryzen 9 5950X'
    assertContains "$out" 'Core Count: 16'
    assertContains "$out" 'Thread Count: 32'
}

testCpuIncludesProcCpuinfo() {
    local out
    out=$(_run 'hwinfo_cpu')
    assertContains 'sekcja /proc/cpuinfo musi się pojawić' "$out" '/proc/cpuinfo:'
    assertContains 'Model z /proc/cpuinfo' "$out" 'Model :'
}

testMotherboardIncludesBiosAndBaseboard() {
    local out
    out=$(_run 'hwinfo_motherboard')
    assertContains "$out" 'TRX40-PRO S'
    assertContains "$out" 'American Megatrends Inc.'
    assertContains "$out" '1401'
}

testRamSkipsEmptySlot() {
    local out
    out=$(_run 'hwinfo_ram')
    assertContains 'zajęty slot musi być widoczny' "$out" 'DIMM_A1'
    assertContains 'zajęty slot musi mieć producenta' "$out" 'Corsair'
    assertNotContains 'pusty slot (No Module Installed) musi być pominięty' "$out" 'DIMM_A2'
}

testGpuFallsBackToLspciAndDmidecode() {
    local out
    out=$(_run 'hwinfo_gpu')
    assertContains 'lspci musi wypisać kartę' "$out" 'NVIDIA Corporation Device 2684'
    assertNotContains 'lspci nie może wypisać niepasujących urządzeń' "$out" 'Intel Corporation'
}

# --- run_diagnostic -----------------------------------------------------------

testRunDiagnosticFailsWhenFixCompMissing() {
    local fake_tools out rc=0
    fake_tools="$(mktemp -d)"
    out=$(WORKSPACE_TOOLS="$fake_tools" bash --norc --noprofile -c "
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh'
        . '$PROJECT_ROOT/bash/functions.d/140_function_diagnostic.sh'
        run_diagnostic
    " 2>&1) || rc=$?
    assertNotEquals 'brak fix-comp musi dać błąd, nie wywalić shella' 0 "$rc"
    assertContains "$out" 'run_diagnostic'
    assertContains "$out" 'brak'
    rm -rf "$fake_tools"
}

testRunDiagnosticInvokesScriptWithArgs() {
    local fake_tools out
    fake_tools="$(mktemp -d)"
    mkdir -p "$fake_tools/fix-comp"
    cat > "$fake_tools/fix-comp/pre-analyze.sh" <<'EOF'
#!/usr/bin/env bash
echo "CALLED_WITH:$*"
EOF
    chmod +x "$fake_tools/fix-comp/pre-analyze.sh"

    out=$(WORKSPACE_TOOLS="$fake_tools" bash --norc --noprofile -c "
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh'
        . '$PROJECT_ROOT/bash/functions.d/140_function_diagnostic.sh'
        run_diagnostic --list-profiles -m
    ")
    assertContains 'run_diagnostic musi przekazać argumenty dalej' "$out" 'CALLED_WITH:--list-profiles -m'
    rm -rf "$fake_tools"
}

testRunDiagnosticPropagatesExitCode() {
    local fake_tools rc=0
    fake_tools="$(mktemp -d)"
    mkdir -p "$fake_tools/fix-comp"
    printf '#!/usr/bin/env bash\nexit 3\n' > "$fake_tools/fix-comp/pre-analyze.sh"
    chmod +x "$fake_tools/fix-comp/pre-analyze.sh"

    WORKSPACE_TOOLS="$fake_tools" bash --norc --noprofile -c "
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh'
        . '$PROJECT_ROOT/bash/functions.d/140_function_diagnostic.sh'
        run_diagnostic
    " >/dev/null 2>&1 || rc=$?
    assertEquals 'kod wyjścia pre-analyze.sh musi się propagować' 3 "$rc"
    rm -rf "$fake_tools"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
