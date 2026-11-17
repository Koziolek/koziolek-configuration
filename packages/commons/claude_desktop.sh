#!/usr/bin/env bash
# Wspólne funkcje install_claude_desktop / update_claude_desktop dla ubuntu/{install,update}.sh.
# Sourcowane, nie wykonywane. Wymaga od skryptu wołającego: $SUDO oraz ok/warn/info.
#
# Claude Desktop na Linuksie (beta) to pakiet .deb z repo apt Anthropic — tylko Debian-based
# (Ubuntu 22.04+, Debian 12+), amd64/arm64. Fedora/RHEL/Arch nieobsługiwane (tam samo CLI).
# https://code.claude.com/docs/en/desktop-linux
#
# Repo i klucz dodaje ta funkcja, zanim spróbuje instalować (idempotentnie). Fingerprint klucza
# jest sprawdzany PRZED wpięciem go do keyringu — niezgodny klucz = brak repo i brak instalacji.
# Pakiet jest beta, więc zanim cokolwiek zainstalujemy, sprawdzamy, czy apt w ogóle widzi
# kandydata (`apt-cache policy`) — brak = ostrzeżenie, nie błąd.
#
# Nieinteraktywne, zawsze `return 0` (błąd = ostrzeżenie, jak `install_claude`/`install_calibre`).
# Zmienne dla testów: CLAUDE_DESKTOP_KEY_URL, CLAUDE_DESKTOP_KEYRING, CLAUDE_DESKTOP_LIST.

CLAUDE_DESKTOP_KEY_URL="${CLAUDE_DESKTOP_KEY_URL:-https://downloads.claude.ai/claude-desktop/key.asc}"
CLAUDE_DESKTOP_KEYRING="${CLAUDE_DESKTOP_KEYRING:-/usr/share/keyrings/claude-desktop-archive-keyring.asc}"
CLAUDE_DESKTOP_LIST="${CLAUDE_DESKTOP_LIST:-/etc/apt/sources.list.d/claude-desktop.list}"
CLAUDE_DESKTOP_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

# Czy ta maszyna może mieć pakiet: apt + amd64/arm64.
_claude_desktop_supported() {
    command -v apt-get >/dev/null 2>&1 || return 1
    case "$(dpkg --print-architecture 2>/dev/null)" in
    amd64 | arm64) return 0 ;;
    *) return 1 ;;
    esac
}

# Kandydat pakietu w apt ("(none)"/pusty = repo nie ma pakietu dla tej architektury).
_claude_desktop_candidate() {
    apt-cache policy claude-desktop 2>/dev/null | awk '/Candidate:/ {print $2; exit}'
}

_claude_desktop_installed() {
    dpkg-query -W -f='${Status}' claude-desktop 2>/dev/null | grep -q "install ok installed"
}

# Klucz + wpis repo (idempotentnie). Zwraca 1 przy błędzie; po dodaniu repo robi `apt-get update`.
_claude_desktop_ensure_repo() {
    if [ -f "$CLAUDE_DESKTOP_LIST" ] && [ -f "$CLAUDE_DESKTOP_KEYRING" ]; then
        return 0
    fi
    local tmp fpr
    tmp="$(mktemp)" || return 1
    if ! curl -fsSLo "$tmp" "$CLAUDE_DESKTOP_KEY_URL"; then
        rm -f "$tmp"
        return 1
    fi
    # Wszystkie fingerprinty z pliku muszą być dokładnie tym jednym — inny klucz = odmowa.
    fpr="$(gpg --show-keys --with-colons "$tmp" 2>/dev/null | awk -F: '$1 == "fpr" {print $10}' | sort -u)"
    if [ "$fpr" != "$CLAUDE_DESKTOP_FPR" ]; then
        rm -f "$tmp"
        warn "Klucz repo Claude Desktop ma nieoczekiwany fingerprint (${fpr:-brak}) — pomijam"
        return 1
    fi
    $SUDO install -m 644 "$tmp" "$CLAUDE_DESKTOP_KEYRING" || {
        rm -f "$tmp"
        return 1
    }
    rm -f "$tmp"
    echo "deb [arch=amd64,arm64 signed-by=$CLAUDE_DESKTOP_KEYRING] https://downloads.claude.ai/claude-desktop/apt/stable stable main" |
        $SUDO tee "$CLAUDE_DESKTOP_LIST" >/dev/null || return 1
    $SUDO apt-get -qq update || return 1
}

# Wspólny rdzeń: repo → sprawdzenie, że pakiet istnieje → apt-get install (instaluje i aktualizuje).
_claude_desktop_apply() {
    if ! _claude_desktop_supported; then
        info "Claude Desktop: tylko Debian/Ubuntu na amd64/arm64 — pomijam"
        return 0
    fi
    if ! _claude_desktop_ensure_repo; then
        warn "Claude Desktop: nie udało się dodać repo apt — pomijam (https://code.claude.com/docs/en/desktop-linux)"
        return 0
    fi
    local candidate
    candidate="$(_claude_desktop_candidate)"
    if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
        warn "Claude Desktop: pakiet claude-desktop niedostępny w apt (beta) — pomijam"
        return 0
    fi
    if $SUDO apt-get install -y claude-desktop; then
        ok "Claude Desktop ${candidate}"
    else
        warn "Claude Desktop: apt-get install claude-desktop zakończony błędem — sprawdź ręcznie"
    fi
    return 0
}

install_claude_desktop() {
    if _claude_desktop_installed; then
        ok "Claude Desktop już zainstalowany"
        return 0
    fi
    info "Instalacja Claude Desktop (repo apt Anthropic)..."
    _claude_desktop_apply
}

# update: zainstaluj lub zaktualizuj w jednej ścieżce (brak pakietu w apt = ostrzeżenie).
update_claude_desktop() {
    echo ""
    echo "=== Claude Desktop ==="
    _claude_desktop_apply
}
