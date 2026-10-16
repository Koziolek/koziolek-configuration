#!/usr/bin/env bash
# Cienki wrapper repair_broken_dkms_packages dla ubuntu/update.sh i vanilla/update.sh.
# Sourcowane, nie wykonywane. Logika siedzi w rejestrze napraw: fixes.d/010_dkms.sh (#144).
#
# Zachowuje dotychczasowy interfejs wywołania; prefiks roota bierze z $SUDO skryptu wołającego
# ('' = root, 'sudo' = z hasłem pod okiem człowieka) zamiast domyślnego `sudo -n` runnera.
# Nigdy nie przerywa skryptu — wynik naprawy jest w raporcie runnera.
_DKMS_FIX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/commons/fixes_runner.sh
. "$_DKMS_FIX_DIR/fixes_runner.sh"

repair_broken_dkms_packages() {
    if [ "${SUDO+x}" = x ]; then
        FIXES_SUDO="$SUDO" run_fixes all --only dkms
    else
        run_fixes all --only dkms
    fi
    return 0
}
