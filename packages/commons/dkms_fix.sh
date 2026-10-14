#!/usr/bin/env bash
# Wspólna funkcja repair_broken_dkms_packages dla ubuntu/update.sh i
# vanilla/update.sh. Sourcowane, nie wykonywane.
#
# Wymaga od skryptu wołającego zdefiniowanych: $SUDO oraz helperów ok/warn/info.

# Pakiet `*-dkms` (np. v4l2loopback-dkms) potrafi utknąć w stanie half-configured:
#   Error! DKMS tree already contains: v4l2loopback-0.12.7
#   You cannot add the same module/version combo more than once.
# postinst robi `dkms add`, a w drzewie DKMS został wpis po poprzedniej wersji (prerm nie
# zdążył go sprzątnąć). Pakiet zostaje w stanie `iF`, a każdy kolejny `apt` wypisuje ten sam
# błąd — nie blokuje, ale daje false-positive w monitoringu.
#
# Naprawa: dla każdego pakietu `*-dkms` w stanie innym niż `ii` usuń z drzewa DKMS moduły
# z jego katalogów /usr/src/<moduł>-<wersja> (`dkms remove --all`), potem dokończ
# konfigurację TYLKO tego pakietu (`dpkg --configure <pkg>`, nie apt — apt przy każdym
# wywołaniu sam domyka niedokończone pakiety i trafiałby w ten sam błąd).
# Idempotentne: gdy wszystkie pakiety dkms są `ii` — nic nie robi. Nigdy nie przerywa
# skryptu (ostrzeżenie zamiast błędu).
repair_broken_dkms_packages() {
    command -v dkms >/dev/null 2>&1 || return 0

    local broken pkg dir name
    broken=$(dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' '*-dkms' 2>/dev/null \
        | awk '$1 != "ii" && $2 != "" {print $2}') || true
    [ -n "$broken" ] || return 0

    for pkg in $broken; do
        warn "Pakiet $pkg nie jest w pełni skonfigurowany — czyszczę drzewo DKMS i dokańczam konfigurację"
        while IFS= read -r dir; do
            name=$(basename "$dir")
            $SUDO dkms remove "${name%-*}/${name##*-}" --all >/dev/null 2>&1 || true
        done < <(dpkg -L "$pkg" 2>/dev/null | grep -E '^/usr/src/[^/]+$' || true)

        if $SUDO dpkg --configure "$pkg" >/dev/null 2>&1; then
            ok "$pkg skonfigurowany"
        else
            warn "Nie udało się dokończyć konfiguracji $pkg — sprawdź ręcznie: sudo dpkg --configure $pkg"
        fi
    done
    return 0
}
