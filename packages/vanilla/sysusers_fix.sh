#!/usr/bin/env bash
# Cienki wrapper fix_sysusers_version_skew dla vanilla/install.sh i vanilla/update.sh.
# Sourcowane, nie wykonywane. Logika siedzi w rejestrze napraw:
# packages/vanilla/fixes.d/010_sysusers.sh (#144) — wykrycie (tylko odczyt) i naprawa osobno.
#
# Wołać po `apt-get update` (świeży indeks dla `apt-get download`), a przed `full-upgrade`/instalacją
# listy pakietów. Prefiks roota bierze z $SUDO skryptu wołającego (FIXES_SUDO). Zawsze `return 0` —
# wynik naprawy jest w raporcie runnera. Od wołającego: $SUDO oraz (opcjonalnie) FIXES_DIRS; domyślnie
# tylko katalog fixes.d obok tego pliku.
_SYSUSERS_FIX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/commons/fixes_runner.sh
. "$_SYSUSERS_FIX_DIR/../commons/fixes_runner.sh"

fix_sysusers_version_skew() {
    local dirs="${FIXES_DIRS:-$_SYSUSERS_FIX_DIR/fixes.d}"
    if [ "${SUDO+x}" = x ]; then
        FIXES_DIRS="$dirs" FIXES_SUDO="$SUDO" run_fixes post-update --only sysusers
    else
        FIXES_DIRS="$dirs" run_fixes post-update --only sysusers
    fi
    return 0
}
