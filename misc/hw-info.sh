#!/usr/bin/env bash
# hw-info.sh – prosty zrzut konfiguracji sprzętowej
# Wymaga: dmidecode (sudo), lspci

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'

header() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${RESET}"; \
           echo -e "${BOLD}${CYAN}  $1${RESET}"; \
           echo -e "${BOLD}${CYAN}══════════════════════════════════════${RESET}"; }

check_deps() {
  local missing=()
  for cmd in dmidecode lspci; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}Brakujące zależności: ${missing[*]}${RESET}"
    echo "Zainstaluj: sudo apt install dmidecode pciutils"
    exit 1
  fi
  if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}Uwaga: dmidecode wymaga uprawnień root. Uruchom przez sudo.${RESET}"
    exit 1
  fi
}

# ── PROCESOR ──────────────────────────────────────────────────────────────────
dump_cpu() {
  header "🖥  PROCESOR"
  dmidecode -t processor | awk '
    /^[[:space:]]*(Socket Designation|Family|Manufacturer|Version|Max Speed|Core Count|Thread Count):/ {
      sub(/^[[:space:]]+/, ""); print "  " $0
    }
  '
  echo
  echo -e "  ${BOLD}/proc/cpuinfo:${RESET}"
  grep -m1 "model name" /proc/cpuinfo | sed 's/model name[[:space:]]*:[[:space:]]*/  Model : /'
  grep -m1 "cpu MHz"    /proc/cpuinfo | sed 's/cpu MHz[[:space:]]*:[[:space:]]*/  Takt  : /' | \
    awk '{printf "  Takt  : %.0f MHz\n", $NF}'
  echo "  Procesory logiczne : $(grep -c "^processor" /proc/cpuinfo)"
}

# ── PŁYTA GŁÓWNA ──────────────────────────────────────────────────────────────
dump_motherboard() {
  header "🔧  PŁYTA GŁÓWNA"
  dmidecode -t baseboard | awk '
    /^[[:space:]]*(Manufacturer|Product Name|Version|Serial Number|Asset Tag):/ {
      sub(/^[[:space:]]+/, ""); print "  " $0
    }
  '
  echo
  header "   BIOS"
  dmidecode -t bios | awk '
    /^[[:space:]]*(Vendor|Version|Release Date|Firmware Revision):/ {
      sub(/^[[:space:]]+/, ""); print "  " $0
    }
  '
}

# ── RAM ───────────────────────────────────────────────────────────────────────
dump_ram() {
  header "💾  PAMIĘĆ RAM"

  local total_gb
  total_gb=$(awk '/MemTotal/ {printf "%.1f GiB", $2/1024/1024}' /proc/meminfo)
  echo -e "  Łącznie zainstalowane: ${BOLD}${total_gb}${RESET}\n"

  dmidecode -t memory | awk '
    /^Memory Device$/ { device++ }
    device && /^[[:space:]]*(Locator|Size|Type|Speed|Manufacturer|Part Number|Form Factor):/ {
      if (/Locator:/ && !/Bank/) slot=$0
      sub(/^[[:space:]]+/, "")
      data[device] = data[device] "\n    " $0
    }
    END {
      for (i=1; i<=device; i++) {
        if (data[i] !~ /No Module Installed/ && data[i] !~ /Size: Unknown/)
          print "  [Slot " i "]" data[i] "\n"
      }
    }
  '
}

# ── KARTA GRAFICZNA ───────────────────────────────────────────────────────────
dump_gpu() {
  header "🎮  KARTA GRAFICZNA"

  echo -e "  ${BOLD}lspci:${RESET}"
  lspci | grep -iE "VGA|3D|Display" | sed 's/^/    /'

  echo
  if command -v nvidia-smi &>/dev/null; then
    echo -e "  ${BOLD}NVIDIA (nvidia-smi):${RESET}"
    nvidia-smi --query-gpu=name,driver_version,memory.total,temperature.gpu \
               --format=csv,noheader | \
      awk -F',' '{
        printf "    Model   : %s\n    Driver  : %s\n    VRAM    : %s\n    Temp    : %s\n", \
               $1, $2, $3, $4
      }'

  elif command -v rocm-smi &>/dev/null; then
    echo -e "  ${BOLD}AMD (rocm-smi):${RESET}"
    rocm-smi --showproductname --showmeminfo vram 2>/dev/null | sed 's/^/    /'

  else
    echo -e "  ${BOLD}Szczegóły (dmidecode):${RESET}"
    dmidecode -t display 2>/dev/null | awk '
      /^[[:space:]]*(Manufacturer|Product Name|Description|Current Video Mode):/ {
        sub(/^[[:space:]]+/, ""); print "    " $0
      }
    '
  fi
}

# ── MAIN ──────────────────────────────────────────────────────────────────────
main() {
  echo -e "${BOLD}hw-info.sh${RESET} – zrzut konfiguracji sprzętowej  $(date '+%Y-%m-%d %H:%M:%S')"
  check_deps
  dump_cpu
  dump_motherboard
  dump_ram
  dump_gpu
  echo -e "\n${CYAN}══════════════════════════════════════${RESET}\n"
}

main "$@"
