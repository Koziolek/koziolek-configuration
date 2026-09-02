#!/usr/bin/env bash
# Kontekst: debian — bazowy dla ubuntu/vanilla/wsl. Ładowany po `linux`.
# Wszystko, co wspólne dla rodziny apt (Debian/Ubuntu/Vanilla/WSL), trzymaj TU,
# nie w liściach — łańcuchy ubuntu/vanilla/wsl i tak przechodzą przez ten plik.

# --- hub przez apt (przeniesione z bash_aliases.sh) -----------------------
# bash_aliases.sh ustawia `alias git=hub`, gdy hub już jest; tu domykamy
# pierwsze uruchomienie (i od razu alias, żeby zadziałał w tej samej powłoce).
if ! command -v hub >/dev/null 2>&1; then
    make_me_sudo
    if $SUDO apt-get update -qq && $SUDO apt-get install -qqy hub; then
        alias git='hub'
    else
        log_warn "hub: instalacja przez apt nieudana — git działa bez aliasu"
    fi
    unmake_me_sudo
fi
