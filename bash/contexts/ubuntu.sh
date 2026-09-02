#!/usr/bin/env bash
# Kontekst: ubuntu. Łańcuch: linux debian ubuntu.
# Rodzina apt (w tym instalacja `hub`) jest w contexts/debian.sh — tu trafia
# tylko to, co swoiste dla Ubuntu, a nie dla całego Debiana.
#
# DOCELOWO (gdy pojawi się potrzeba):
#   • komponent repo `universe` (add-apt-repository universe)
#   • ścieżki/aliasy snap
#
# Na razie brak nadpisań — Ubuntu = linux + debian.
