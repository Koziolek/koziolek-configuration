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

# _dkms_purge_tree <moduł> <wersja> — ostatnia deska, gdy `dkms remove --all` zostawił wpis: usuwa
# katalog drzewa DKMS tej wersji i wiszące symlinki kernel-*. Nazwy walidowane (to idzie do `rm -rf`).
# DKMS_TREE_DIR (domyślnie /var/lib/dkms) pozwala testom nie dotykać systemu.
_dkms_purge_tree() {
    local mod="$1" ver="$2" tree="${DKMS_TREE_DIR:-/var/lib/dkms}" link
    [[ "$mod" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ && "$ver" =~ ^[A-Za-z0-9][A-Za-z0-9._+~-]*$ ]] || return 1
    $SUDO rm -rf -- "$tree/$mod/$ver"
    for link in "$tree/$mod"/kernel-*; do
        [ -L "$link" ] && [ ! -e "$link" ] && $SUDO rm -f -- "$link"
    done
    return 0
}

# Pakiet *-dkms bywa nie do naprawienia samym `dkms remove --all`: drzewo trzyma wpisy dla kerneli,
# które już odinstalowano ("Missing some built modules"), remove się o nie potyka i zostawia moduł —
# wtedy postinst znów kończy się "DKMS tree already contains". Dlatego po remove sprawdzamy
# `dkms status`, a gdy wpis został, czyścimy drzewo ręcznie (to tylko artefakty builda, postinst
# zbuduje moduł od nowa). Błędy poleceń są logowane, nie połykane.
fix_apply() {
    local broken pkg dir name mod ver out rc=0
    broken=$(_dkms_broken_packages)
    for pkg in $broken; do
        fix_log "pakiet %s nie jest w pełni skonfigurowany — czyszczę drzewo DKMS i dokańczam konfigurację" "$pkg"
        while IFS= read -r dir; do
            name=$(basename "$dir")
            mod="${name%-*}"
            ver="${name##*-}"
            out=$($SUDO dkms remove "$mod/$ver" --all 2>&1) \
                || fix_log "dkms remove %s/%s: %s" "$mod" "$ver" "$(printf '%s' "$out" | tail -n 1)"
            if [ -n "$($SUDO dkms status "$mod/$ver" 2>/dev/null)" ]; then
                fix_log "dkms remove zostawił %s/%s w drzewie — czyszczę ręcznie" "$mod" "$ver"
                _dkms_purge_tree "$mod" "$ver" || fix_log "nieprawidłowa nazwa modułu %s/%s — pomijam" "$mod" "$ver"
            fi
        done < <(dpkg -L "$pkg" 2>/dev/null | grep -E '^/usr/src/[^/]+$' || true)

        if out=$($SUDO dpkg --configure "$pkg" 2>&1); then
            fix_log "%s skonfigurowany" "$pkg"
        else
            fix_log "dpkg --configure %s: %s" "$pkg" "$(printf '%s' "$out" | tail -n 3 | tr '\n' ' ')"
            fix_log "nie udało się dokończyć konfiguracji %s — sprawdź ręcznie: sudo dpkg --configure %s" "$pkg" "$pkg"
            rc=1
        fi
    done
    return $rc
}

fix_verify() {
    [ -z "$(_dkms_broken_packages)" ]
}
