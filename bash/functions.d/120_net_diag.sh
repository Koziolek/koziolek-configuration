#!/usr/bin/env bash

# netconf_diag.sh - Diagnostyka zrywania połączeń podczas telekonferencji
# Użycie:
#   sudo netconf_diag              # domyślnie 15 minut, host 1.1.1.1
#   sudo netconf_diag -d 30 -t 8.8.8.8
#   sudo netconf_diag -i wlp2s0    # wymuszenie interfejsu

function netconf_diag() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    log_warn "netconf_diag: wymaga narzędzi Linux (ip, iw, nmcli, journalctl) — niedostępnych na macOS"
    return 1
  fi
  make_me_sudo
  local DURATION_MIN=15
  local TARGET="1.1.1.1"
  local IFACE=""
  local OUTDIR=""
  local INTERVAL=1

  need_cmd() { command -v "$1" >/dev/null 2>&1; }

  usage() {
    cat <<EOF
Użycie: netconf_diag [-d minuty] [-t host] [-i interfejs] [-o katalog]
  -d  czas działania w minutach (domyślnie: ${DURATION_MIN})
  -t  host do testu (domyślnie: ${TARGET})
  -i  interfejs sieciowy (np. eth0/wlp2s0); jeśli puste, wykryje sam
  -o  katalog wyjściowy (domyślnie: /tmp/netconf-YYYYmmdd-HHMMSS)
EOF
  }

  while getopts ":d:t:i:o:h" opt; do
    case "$opt" in
    d) DURATION_MIN="$OPTARG" ;;
    t) TARGET="$OPTARG" ;;
    i) IFACE="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    h)
      usage
      unmake_me_sudo
      return 0
      ;;
    \?)
      echo "Nieznana opcja: -$OPTARG" >&2
      usage
      unmake_me_sudo
      return 2
      ;;
    :)
      echo "Brak argumentu dla -$OPTARG" >&2
      usage
      unmake_me_sudo
      return 2
      ;;
    esac
  done

  if [[ $EUID -ne 0 ]]; then
    echo "Uruchom jako root (sudo), bo będziemy czytać logi i info o Wi-Fi." >&2
    unmake_me_sudo
    return 1
  fi

  local TS="$(date +%Y%m%d-%H%M%S)"
  OUTDIR="${OUTDIR:-/tmp/netconf-$TS}"
  mkdir -p "$OUTDIR"

  local LOG="$OUTDIR/monitor.log"
  local EVENTS="$OUTDIR/events.log"
  local SYSINFO="$OUTDIR/sysinfo.txt"
  local MTRLOG="$OUTDIR/mtr_${TARGET}.txt"
  local WIFILOG="$OUTDIR/wifi.log"

  echo "== netconf_diag start: $(date -Is) ==" | tee -a "$LOG"
  echo "Output: $OUTDIR" | tee -a "$LOG"
  echo "Duration: ${DURATION_MIN} min, Target: ${TARGET}" | tee -a "$LOG"

  # Wykryj interfejs, jeśli nie podany
  if [[ -z "${IFACE}" ]]; then
    IFACE="$(ip route get "$TARGET" 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1 || true)"
    IFACE="${IFACE:-$(ip route | awk '/default/ {print $5; exit}')}"
  fi
  if [[ -z "${IFACE}" ]]; then
    echo "Nie udało się wykryć interfejsu. Podaj -i <iface>." | tee -a "$LOG"
    unmake_me_sudo
    return 1
  fi

  local GW="$(ip route | awk '/default/ {print $3; exit}')"
  GW="${GW:-}"
  echo "Interface: $IFACE" | tee -a "$LOG"
  echo "Gateway: ${GW:-unknown}" | tee -a "$LOG"

  {
    echo "### BASIC ###"
    uname -a
    date -Is
    echo
    echo "### IP ADDR ###"
    ip addr show
    echo
    echo "### ROUTES ###"
    ip route show
    echo
    echo "### RESOLV ###"
    cat /etc/resolv.conf 2>/dev/null || true
    echo
    echo "### NMCLI (if available) ###"
    if need_cmd nmcli; then
      nmcli -p general status
      nmcli -p dev status
    fi
    echo
    echo "### WIFI (if available) ###"
    if need_cmd iw; then iw dev 2>/dev/null || true; fi
  } >"$SYSINFO"

  # Funkcja: snapshot stanu sieci w momencie problemu
  snapshot() {
    local label="$1"
    {
      echo "----- SNAPSHOT: $label @ $(date -Is) -----"
      ip -s link show dev "$IFACE" || true
      ip addr show dev "$IFACE" || true
      ip route show || true
      ss -tpna || true
      if need_cmd nmcli; then nmcli -p dev show "$IFACE" || true; fi
      if need_cmd journalctl; then
        echo "### journalctl (NetworkManager) last 200 lines ###"
        journalctl -u NetworkManager -n 200 --no-pager 2>/dev/null || true
        echo "### journalctl (kernel/net) last 200 lines ###"
        journalctl -k -n 200 --no-pager 2>/dev/null || true
      fi
    } >>"$EVENTS"
  }

  # mtr w tle (jeśli jest)
  local MTR_PID=""
  if need_cmd mtr; then
    echo "Starting mtr (chunked)..." | tee -a "$LOG"
    (
      while true; do
        echo "===== $(date -Is) =====" >> "$MTRLOG"
        mtr -r -w -c 20 -i 0.2 "$TARGET" >> "$MTRLOG" 2>&1
        echo >> "$MTRLOG"
        sleep 10
      done
    ) &
    MTR_PID=$!
  else
    echo "mtr not found (np. sudo apt install mtr-tiny)." | tee -a "$LOG"
  fi

  # Wi-Fi telemetry w tle (jeśli iface jest bezprzewodowy)
  local WIFI_PID=""
  if need_cmd iw && iw dev "$IFACE" info >/dev/null 2>&1; then
    echo "Wi-Fi interface detected, logging signal/bitrate..." | tee -a "$LOG"
    (
      while true; do
        {
          printf "%s " "$(date -Is)"
          iw dev "$IFACE" link 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g'
          echo
        } >>"$WIFILOG"
        sleep 2
      done
    ) &
    WIFI_PID=$!
  else
    echo "Wi-Fi telemetry skipped (no iw or iface not wireless)." | tee -a "$LOG"
  fi

  # Monitor pingu
  local END_EPOCH=$(($(date +%s) + DURATION_MIN * 60))
  local FAIL_STREAK=0

  echo "Monitoring started..." | tee -a "$LOG"
  snapshot "START"

  while [[ $(date +%s) -lt $END_EPOCH ]]; do
    local OK_GW=1
    local OK_NET=1

    if [[ -n "${GW}" ]]; then
      ping -n -c 1 -W 1 -I "$IFACE" "$GW" >/dev/null 2>&1 || OK_GW=0
    fi
    ping -n -c 1 -W 1 -I "$IFACE" "$TARGET" >/dev/null 2>&1 || OK_NET=0

    local RTT=""
    if [[ $OK_NET -eq 1 ]]; then
      RTT="$(ping -n -c 1 -W 1 -I "$IFACE" "$TARGET" 2>/dev/null | awk -F'time=' '/time=/{print $2}' | awk '{print $1" ms"}' | head -n1)"
    fi

    echo "$(date -Is) gw=${OK_GW} net=${OK_NET} rtt=${RTT:-na}" >>"$LOG"

    if [[ $OK_NET -eq 0 ]]; then
      FAIL_STREAK=$((FAIL_STREAK + 1))
      if [[ $FAIL_STREAK -eq 2 ]]; then
        echo "$(date -Is) EVENT: connectivity_drop (2 consecutive fails)" >>"$EVENTS"
        snapshot "CONNECTIVITY_DROP"
      fi
    else
      if [[ $FAIL_STREAK -ge 2 ]]; then
        echo "$(date -Is) EVENT: connectivity_restored (after ${FAIL_STREAK} fails)" >>"$EVENTS"
        snapshot "CONNECTIVITY_RESTORED"
      fi
      FAIL_STREAK=0
    fi

    sleep "$INTERVAL"
  done

  snapshot "END"

  # Sprzątanie procesów w tle
  if [[ -n "${MTR_PID}" ]]; then
    kill "$MTR_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${WIFI_PID}" ]]; then
    kill "$WIFI_PID" >/dev/null 2>&1 || true
  fi

  # Paczka wyników
  local TAR="$OUTDIR.tar.gz"
  tar -czf "$TAR" -C "$(dirname "$OUTDIR")" "$(basename "$OUTDIR")"

  echo "== done: $(date -Is) ==" | tee -a "$LOG"
  echo "Wyniki spakowane: $TAR"
  echo "Najważniejsze pliki:"
  echo " - $LOG"
  echo " - $EVENTS"
  echo " - $MTRLOG (jeśli mtr jest zainstalowany)"
  echo " - $WIFILOG (jeśli Wi-Fi)"

  unmake_me_sudo
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f netconf_diag
else
  netconf_diag "$@"
fi
