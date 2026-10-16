#!/usr/bin/env bash
# Wrapper cleanup_stale_sources dla vanilla/update.sh. Sourcowane, nie wykonywane.
# Logika siedzi w rejestrze napraw: packages/vanilla/fixes.d/005_stale_sources.sh (#144).
#
# Fix ma FIX_RISK=high i nie pyta o nic (stdin z /dev/null), więc zgoda człowieka jest tu:
# update_* leci pod okiem użytkownika. Wykrycie przez `--check`, pytanie, potem apply z
# `--allow-high`. Bez TTY/odpowiedzi => domyślnie „nie”. Wymaga wcześniej załadowanego
# fixes_runner.sh (dkms_fix.sh go ładuje) oraz FIXES_DIRS z katalogiem packages/vanilla/fixes.d,
# a od wołającego helperów ok/warn/info i $SUDO.
cleanup_stale_sources() {
    echo ""
    echo "=== Martwe źródła apt ==="
    local rc=0 reply=n
    run_fixes pre-apt --only stale-sources --check >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0) ok "Brak martwych źródeł do wyczyszczenia"; return 0 ;;
        10) ;;
        *) warn "Nie udało się sprawdzić martwych źródeł apt (kod $rc)"; return 0 ;;
    esac

    warn "docker.list obecny, ale Docker niezainstalowany (Vanilla używa podmana)."
    read -r -p "Usunąć /etc/apt/sources.list.d/docker.list (+ keyring)? [y/N]: " -n 1 reply || reply=n
    echo
    if [[ "$reply" =~ ^[YyTt]$ ]]; then
        if FIXES_SUDO="${SUDO-}" run_fixes pre-apt --only stale-sources --allow-high --strict >/dev/null 2>&1; then
            ok "docker.list usunięty"
        else
            warn "Nie udało się usunąć docker.list — sprawdź ręcznie: sudo rm /etc/apt/sources.list.d/docker.list"
        fi
    else
        info "Pominięto usuwanie docker.list"
    fi
    return 0
}
