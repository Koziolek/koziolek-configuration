#!/usr/bin/env bash
# Testy jednostkowe: podpięcie rejestru napraw (#144) w skryptach packages/*/{install,update}.sh.
# Pilnuje, że apt-owe skrypty wołają fazy pre-apt/post-apt (bez nich uszkodzony pakiet *-dkms
# blokuje każdy apt-get install) i że robią to w dobrej kolejności względem instalacji pakietów.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# _line <plik> <wzorzec> — numer pierwszej linii (poza komentarzami) pasującej do wzorca; pusty = brak
_line() {
    grep -nE "$2" "$PROJECT_ROOT/packages/$1" | grep -vE '^[0-9]+:[[:space:]]*#' | head -1 | cut -d: -f1
}

_assert_wired() {
    local f="$1" pre post inst
    pre="$(_line "$f" 'apply_fixes pre-apt')"
    post="$(_line "$f" 'apply_fixes post-apt')"
    assertNotEquals "$f: brak apply_fixes pre-apt" "" "$pre"
    assertNotEquals "$f: brak apply_fixes post-apt" "" "$post"
    assertTrue "$f: pre-apt przed post-apt" "[ '${pre:-0}' -lt '${post:-0}' ]"
}

testUbuntuInstallRunsAptFixes()  { _assert_wired ubuntu/install.sh; }
testUbuntuUpdateRunsAptFixes()   { _assert_wired ubuntu/update.sh; }
testVanillaInstallRunsAptFixes() { _assert_wired vanilla/install.sh; }
testVanillaUpdateRunsAptFixes()  { _assert_wired vanilla/update.sh; }

testInstallFixesBracketPackageInstallation() {
    local f pre post inst
    for f in ubuntu/install.sh vanilla/install.sh; do
        pre="$(_line "$f" 'apply_fixes pre-apt')"
        post="$(_line "$f" 'apply_fixes post-apt')"
        inst="$(_line "$f" 'safe_apt_install "\$\{all_packages')"
        assertTrue "$f: pre-apt przed instalacją listy pakietów" "[ '${pre:-999}' -lt '${inst:-0}' ]"
        assertTrue "$f: post-apt po instalacji listy pakietów" "[ '${post:-0}' -gt '${inst:-999}' ]"
    done
}

testAptInstallersRefreshAptLogBeforeFixes() {
    local f log pre
    for f in ubuntu/install.sh vanilla/install.sh; do
        log="$(_line "$f" 'fixes_refresh_apt_log')"
        pre="$(_line "$f" 'apply_fixes pre-apt')"
        assertTrue "$f: log apt-get update (dla apt-gpg) przed pre-apt" "[ '${log:-999}' -lt '${pre:-0}' ]"
    done
}

testNonAptSystemsDoNotCallAptFixes() {
    local f
    for f in redhat/install.sh redhat/update.sh mac/install.sh mac/update.sh; do
        assertEquals "$f nie woła apply_fixes pre-apt" "" "$(_line "$f" 'apply_fixes pre-apt')"
    done
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
