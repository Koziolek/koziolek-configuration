#!/usr/bin/env bash
# Kontekst: redhat (RHEL/CentOS/Fedora/Rocky/Alma). Ładowany po `linux`.
# Wszystko, co wspólne dla rodziny yum, trzymaj TU (analog contexts/debian.sh).

# --- hub przez yum ----------------------------------------------------------
# Fedora ma `hub` w domyślnych repo; RHEL/CentOS bez EPEL może nie mieć —
# przy niepowodzeniu git działa dalej bez aliasu (tak jak w debian.sh).
if ! command -v hub >/dev/null 2>&1; then
    make_me_sudo
    if $SUDO yum install -y hub; then
        alias git='hub'
    else
        log_warn "hub: instalacja przez yum nieudana — git działa bez aliasu"
    fi
    unmake_me_sudo
fi
