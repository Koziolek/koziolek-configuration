#!/usr/bin/env bash
# Wspólna funkcja fix_sysusers_version_skew dla initial_packages_vanilla.sh i
# update_packages_vanilla.sh. Sourcowane, nie wykonywane.
#
# Wymaga od skryptu wołającego zdefiniowanej wcześniej (przed WYWOŁANIEM, nie przed
# source'owaniem tego pliku) zmiennej $SUDO.

# Pakiety bywają spakowane z sysusers.d, który używa nowszej składni (np.
# modyfikator `u!`, dodany w systemd 257 — tak ma pcscd ≥2.5.2) niż binarka
# sysusers faktycznie obsługuje. Kontener apx nie ma pełnego systemd, tylko
# minimalny `systemd-standalone-sysusers` — a nic w `Depends:` pcscd nie
# wymusza jego wersji, więc apt nie podciąga go automatycznie przy instalacji
# security_tools. Rozjazd wersji psuje postinst ("Unknown modifier 'u!'").
#
# Zwykłe `apt-get install --only-upgrade` tu NIE wystarczy: skoro pcscd już
# raz padł, apt przy KAŻDYM kolejnym wywołaniu najpierw samo próbuje domknąć
# pozostawiony w stanie "half-configured" pcscd (ten sam błąd, zanim zdąży
# podciągnąć nowszy sysusers) — stąd błąd wciąż wraca nawet po dodaniu tego
# kroku, jeśli maszyna już wcześniej ugrzęzła na tym pakiecie. Obchodzimy to
# przez goły `dpkg -i`: w przeciwieństwie do apt, dpkg wywołane z konkretnym
# plikiem konfiguruje TYLKO ten pakiet, nie dotykając innych pozostawionych
# w locie — więc nowszy sysusers ląduje skonfigurowany PRZED jakimkolwiek
# `apt-get install`/`full-upgrade`, które by wywołało tę pułapkę.
#
# Wołać po `apt-get update` (żeby `apt-get download` brał najnowszą wersję),
# a przed `full-upgrade`/instalacją listy pakietów.
fix_sysusers_version_skew() {
    local sysusers_bin owner_pkg tmp_dir
    sysusers_bin=$(command -v systemd-sysusers 2>/dev/null) || return 0
    owner_pkg=$(dpkg -S "$sysusers_bin" 2>/dev/null | cut -d: -f1 | head -1)
    [ -n "$owner_pkg" ] || return 0

    tmp_dir=$(mktemp -d)
    (
        cd "$tmp_dir" || exit 0
        $SUDO apt-get download "$owner_pkg" >/dev/null 2>&1 || exit 0
        $SUDO dpkg -i "${owner_pkg}"_*.deb >/dev/null 2>&1 || true
    )
    rm -rf "$tmp_dir"
}
