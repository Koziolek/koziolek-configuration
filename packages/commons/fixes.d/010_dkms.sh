#!/usr/bin/env bash
# Fix `dkms`: pakiet `*-dkms` utknął w stanie half-configured. Sourcowane przez runner
# (packages/commons/fixes_runner.sh), niczego nie wykonuje przy source'owaniu.
#
# Pakiet `*-dkms` (np. v4l2loopback-dkms) potrafi utknąć w stanie `iF`:
#   Error! DKMS tree already contains: v4l2loopback-0.12.7
#   You cannot add the same module/version combo more than once.
# postinst robi `dkms add`, a w drzewie DKMS został wpis po poprzedniej wersji (prerm nie
# zdążył go sprzątnąć). Każdy kolejny `apt` wypisuje ten sam błąd — nie blokuje, ale daje
# false-positive w monitoringu.
#
# Naprawa: dla każdego takiego pakietu usuń z drzewa DKMS moduły z jego katalogów
# /usr/src/<moduł>-<wersja> (`dkms remove --all`), potem dokończ konfigurację TYLKO tego pakietu
# (`dpkg --configure <pkg>`, nie apt — apt przy każdym wywołaniu sam domyka niedokończone pakiety
# i trafiałby w ten sam błąd).

FIX_ID=dkms
FIX_DESC="pakiety *-dkms w stanie half-configured (Error! DKMS tree already contains)"
FIX_PHASE="pre-apt post-apt"
FIX_CONTEXTS=debian
FIX_NEEDS_ROOT=1
FIX_RISK=low

# _dkms_broken_packages — pakiety `*-dkms` z dodatnim dowodem uszkodzenia w bazie dpkg: pożądany stan
# `i` (install), status F/H/U/W/T (half-configured/half-installed/unpacked/trig-awaited/trig-pending).
# `rc`/`un` i inne stany usunięte NIE są uszkodzone i nie są ruszane.
_dkms_broken_packages() {
    dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' '*-dkms' 2>/dev/null \
        | awk 'substr($1,1,1) == "i" && substr($1,2,1) ~ /[FHUWT]/ && $2 != "" {print $2}'
}

fix_detect() {
    command -v dkms >/dev/null 2>&1 || return 2
    command -v dpkg-query >/dev/null 2>&1 || return 3
    local broken
    broken=$(_dkms_broken_packages | tr '\n' ' ')
    broken="${broken% }"
    [ -n "$broken" ] || return 1
    fix_detail "$broken"
    return 0
}

fix_apply() {
    local broken pkg dir name rc=0
    broken=$(_dkms_broken_packages)
    for pkg in $broken; do
        fix_log "pakiet %s nie jest w pełni skonfigurowany — czyszczę drzewo DKMS i dokańczam konfigurację" "$pkg"
        while IFS= read -r dir; do
            name=$(basename "$dir")
            $SUDO dkms remove "${name%-*}/${name##*-}" --all >/dev/null 2>&1 || true
        done < <(dpkg -L "$pkg" 2>/dev/null | grep -E '^/usr/src/[^/]+$' || true)

        if $SUDO dpkg --configure "$pkg" >/dev/null 2>&1; then
            fix_log "%s skonfigurowany" "$pkg"
        else
            fix_log "nie udało się dokończyć konfiguracji %s — sprawdź ręcznie: sudo dpkg --configure %s" "$pkg" "$pkg"
            rc=1
        fi
    done
    return $rc
}

fix_verify() {
    [ -z "$(_dkms_broken_packages)" ]
}
