#!/usr/bin/env bash
# Kontekst: darwin (macOS). Jedyne ogniwo łańcucha dla macOS.
# Ładowany po wspólnej konfiguracji (bash_exports/aliases/misc) i po functions.d/,
# przed bash_customs — więc może cieniować (redefiniować) funkcje z functions.d/.

# --- Homebrew (przeniesione z bash_exports.sh) ------------------------------
if [ -d /opt/homebrew ]; then
    export HOMEBREW_PREFIX="/opt/homebrew"
elif [ -d /usr/local/Homebrew ]; then
    export HOMEBREW_PREFIX="/usr/local"
fi
if [ -n "${HOMEBREW_PREFIX:-}" ]; then
    export HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar"
    export HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX/Homebrew"
    export INFOPATH="$HOMEBREW_PREFIX/share/info:${INFOPATH:-}"
    export MANPATH="$HOMEBREW_PREFIX/share/man:${MANPATH:-}"

    # Zachowaj pierwszeństwo narzędzi użytkownika nad Homebrew — tak jak wtedy,
    # gdy blok Homebrew był w bash_exports.sh przed liniami PATH .local/bin + shims.
    # bash_exports.sh już wstawił oba katalogi do PATH — usuwamy te wystąpienia
    # przed ponownym doklejeniem z przodu, żeby nie zdublować wpisów.
    _local_bin="$HOME/.local/bin"
    _asdf_shims="${ASDF_DATA_DIR:-$HOME/.asdf}/shims"
    _rest=":$PATH:"
    _rest="${_rest//:$_local_bin:/:}"
    _rest="${_rest//:$_asdf_shims:/:}"
    _rest="${_rest#:}"; _rest="${_rest%:}"
    export PATH="$_local_bin:$_asdf_shims:$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:$_rest"
    unset _local_bin _asdf_shims _rest
fi

# --- Compose ---------------------------------------------------------------
# macOS: compose = plugin Dockera (nie ma podman-compose). Probe w bash_exports.sh
# zwykle to złapie; ustawiamy jawnie dla pewności.
if command -v docker >/dev/null 2>&1; then
    export DOCKER_COMPOSE="docker compose"
fi

# --- hub przez brew (przeniesione z bash_aliases.sh) ----------------------
if ! command -v hub >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
    brew install hub && alias git='hub'
fi

# --- Aliasy swoiste dla macOS (przeniesione z bash_aliases.sh) -------------
alias in-window='open'
alias alert='osascript -e "display notification \"$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')\""'
alias ls='ls -G'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
command -v gtime >/dev/null 2>&1 && alias time="gtime -f '\t%E real,\t%U user,\t%S sys,\t%K avg_mem,\t%M max_mem,\t%%I IO_ins\t%O IO_outs'"

# --- Cieniowanie funkcji zależnych od Linuksa (z functions.d/) -------------
# Na macOS brak /proc, ss, swapoff, systemd, ip/iw/nmcli, apt. functions.d/
# trzyma tylko wersję Linux (bez guardów uname), a tu ją nadpisujemy.

# who_use_port: część zbierająca gniazda — na macOS lsof zamiast ss.
_listening_socket_pairs() {
    $SUDO lsof -iTCP -iUDP -sTCP:LISTEN -n -P 2>/dev/null \
      | awk 'NR>1 && match($0, /:[0-9]+[[:space:]]*\(LISTEN\)/) {
          seg = substr($0, RSTART, RLENGTH)
          p = seg
          gsub(/[^0-9]/, "", p)
          if (p != "") print $2":"p
        }'
}

# hwinfo (functions.d/125_function_hwinfo.sh): wersja Linux liczy na dmidecode/lspci/proc —
# na macOS zamiennik to system_profiler/sysctl/sw_vers, bez roota. Orkiestrator hwinfo()
# zostaje wspólny.
_hwinfo_check_deps() { return 0; }

hwinfo_cpu() {
    _hwinfo_header "🖥  PROCESOR"
    echo "  Model : $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
    local chip
    chip=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip:/ {print $2}')
    [ -n "$chip" ] && echo "  Chip  : $chip"
    echo "  Rdzenie fizyczne   : $(sysctl -n hw.physicalcpu 2>/dev/null)"
    echo "  Rdzenie logiczne   : $(sysctl -n hw.logicalcpu 2>/dev/null)"
    local hz
    hz=$(sysctl -n hw.cpufrequency_max 2>/dev/null)
    # Apple Silicon nie eksponuje hw.cpufrequency_max — pomijamy, jeśli puste/0.
    if [ -n "$hz" ] && [ "$hz" != "0" ]; then
        awk -v hz="$hz" 'BEGIN{printf "  Takt (max)         : %.0f MHz\n", hz/1000000}'
    fi
}

hwinfo_motherboard() {
    _hwinfo_header "🔧  MODEL MAC"
    system_profiler SPHardwareDataType 2>/dev/null | awk '
      /Model Name:|Model Identifier:|Chip:|Processor Name:|Serial Number|Hardware UUID:/ {
        sub(/^[[:space:]]+/, ""); print "  " $0
      }
    '
    echo
    _hwinfo_header "   FIRMWARE / OS"
    echo "  macOS : $(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null) (build $(sw_vers -buildVersion 2>/dev/null))"
}

hwinfo_ram() {
    _hwinfo_header "💾  PAMIĘĆ RAM"
    local bytes total_gb
    bytes=$(sysctl -n hw.memsize 2>/dev/null)
    total_gb=$(awk -v b="$bytes" 'BEGIN{printf "%.1f GiB", b/1024/1024/1024}')
    echo "  Łącznie zainstalowane: ${C_BOLD}${total_gb}${C_NC}"
    echo
    system_profiler SPMemoryDataType 2>/dev/null | awk '
      /BANK|Size:|Type:|Speed:|Manufacturer:|Status:/ {
        sub(/^[[:space:]]+/, ""); print "  " $0
      }
    '
}

hwinfo_gpu() {
    _hwinfo_header "🎮  KARTA GRAFICZNA"
    system_profiler SPDisplaysDataType 2>/dev/null | awk '
      /Chipset Model:|VRAM|Vendor:|Metal/ {
        sub(/^[[:space:]]+/, ""); print "  " $0
      }
    '
}

# detect_display_env: wersja z functions.d/ nie zna macOS (usunęliśmy guard uname).
detect_display_env() { echo "darwin"; }

reswap() { log_warn "reswap: swapoff/swapon niedostępne na macOS"; return 1; }
who_use_swap() { log_warn "who_use_swap: /proc niedostępny na macOS"; return 1; }
turn_async_profiler_on() { log_warn "turn_async_profiler_on: /proc/sys/kernel nie istnieje na macOS"; return 1; }
turn_async_profiler_off() { log_warn "turn_async_profiler_off: /proc/sys/kernel nie istnieje na macOS"; return 1; }
start_x() { log_warn "start_x: systemctl/lightdm niedostępne na macOS"; return 1; }
netconf_diag() { log_warn "netconf_diag: wymaga narzędzi Linux (ip, iw, nmcli, journalctl) — niedostępnych na macOS"; return 1; }
refresh_apt_gpg_keys() { log_warn "refresh_apt_gpg_keys: apt niedostępne na macOS"; return 1; }

export -f _listening_socket_pairs detect_display_env reswap who_use_swap \
    turn_async_profiler_on turn_async_profiler_off start_x netconf_diag refresh_apt_gpg_keys \
    _hwinfo_check_deps hwinfo_cpu hwinfo_motherboard hwinfo_ram hwinfo_gpu
