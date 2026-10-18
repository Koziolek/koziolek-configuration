#!/usr/bin/env bash
# Wspólna funkcja calibre_install_deps dla {ubuntu,vanilla,redhat}/{install,update}.sh.
# Sourcowane, nie wykonywane. Wołane PRZED oficjalnym instalatorem calibre.
#
# Binarka calibre ładuje wtyczkę Qt `xcb`, której brakuje biblioteki libxcb-cursor
# (bez niej: "Could not load the Qt platform plugin xcb"). Na Vanilla OS (subsystem apx)
# i w minimalnych instalacjach pakietu nie ma w standardzie.
#   apt: libxcb-cursor0     yum/dnf: xcb-util-cursor
#
# Nieinteraktywne, zawsze `return 0` — błąd to ostrzeżenie (calibre i tak się zainstaluje,
# tylko GUI może nie wystartować). Wymaga $SUDO ustawionego przez skrypt wołający.

calibre_install_deps() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "Zależności calibre (libxcb-cursor0)..."
        $SUDO apt-get install -qqy libxcb-cursor0 \
            || echo "⚠️  libxcb-cursor0 niezainstalowany — GUI calibre może nie wystartować: sudo apt-get install libxcb-cursor0"
    elif command -v yum >/dev/null 2>&1; then
        echo "Zależności calibre (xcb-util-cursor)..."
        $SUDO yum install -y xcb-util-cursor \
            || echo "⚠️  xcb-util-cursor niezainstalowany — GUI calibre może nie wystartować: sudo yum install xcb-util-cursor"
    fi
    return 0
}
