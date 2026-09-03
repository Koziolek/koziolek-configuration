#!/usr/bin/env bash
#
# hwinfo — zrzut konfiguracji sprzętowej (CPU, płyta główna/BIOS, RAM, GPU).
# Przeniesione z misc/hw-info.sh (był samodzielnym skryptem — teraz funkcja powłoki).
#
# Wersja tu = Linux (dmidecode/lspci/proc — te same narzędzia na Ubuntu/Debian/Vanilla
# i RedHat/CentOS/Fedora, w obu `packages/*_packages.sh` jest `dmidecode`+`pciutils`/
# `lspci`). macOS nie ma dmidecode/lspci/proc — bash/contexts/darwin.sh cieniuje
# `_hwinfo_check_deps`/`hwinfo_cpu`/`hwinfo_motherboard`/`hwinfo_ram`/`hwinfo_gpu`
# wersją opartą o `system_profiler`/`sysctl`. Orkiestrator `hwinfo()` zostaje wspólny
# (ten sam wzorzec co `resize_to_full` + `detect_display_env`).

_hwinfo_header() {
  echo "${C_BOLD}${C_CYAN}══════════════════════════════════════${C_NC}"
  echo "${C_BOLD}${C_CYAN}  $1${C_NC}"
  echo "${C_BOLD}${C_CYAN}══════════════════════════════════════${C_NC}"
}

# Wymaga: dmidecode (root), lspci (pciutils). Cieniowane na macOS (darwin.sh).
_hwinfo_check_deps() {
  local missing=()
  local cmd
  for cmd in dmidecode lspci; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    log_error "hwinfo: brakujące zależności: ${missing[*]}"
    log_info "hwinfo: zainstaluj: sudo apt install dmidecode pciutils   (albo: sudo yum install dmidecode pciutils)"
    return 1
  fi
  if [ "$EUID" -ne 0 ]; then
    log_warn "hwinfo: dmidecode wymaga uprawnień root — uruchom przez sudo"
    return 1
  fi
  return 0
}

# ── PROCESOR ──────────────────────────────────────────────────────────────
hwinfo_cpu() {
  _hwinfo_header "🖥  PROCESOR"
  dmidecode -t processor | awk '
    /^[[:space:]]*(Socket Designation|Family|Manufacturer|Version|Max Speed|Core Count|Thread Count):/ {
      sub(/^[[:space:]]+/, ""); print "  " $0
    }
  '
  echo
  echo "  ${C_BOLD}/proc/cpuinfo:${C_NC}"
  grep -m1 "model name" /proc/cpuinfo | sed 's/model name[[:space:]]*:[[:space:]]*/  Model : /'
  grep -m1 "cpu MHz"    /proc/cpuinfo | sed 's/cpu MHz[[:space:]]*:[[:space:]]*/  Takt  : /' | \
    awk '{printf "  Takt  : %.0f MHz\n", $NF}'
  echo "  Procesory logiczne : $(grep -c "^processor" /proc/cpuinfo)"
}

# ── PŁYTA GŁÓWNA ──────────────────────────────────────────────────────────
hwinfo_motherboard() {
  _hwinfo_header "🔧  PŁYTA GŁÓWNA"
  dmidecode -t baseboard | awk '
    /^[[:space:]]*(Manufacturer|Product Name|Version|Serial Number|Asset Tag):/ {
      sub(/^[[:space:]]+/, ""); print "  " $0
    }
  '
  echo
  _hwinfo_header "   BIOS"
  dmidecode -t bios | awk '
    /^[[:space:]]*(Vendor|Version|Release Date|Firmware Revision):/ {
      sub(/^[[:space:]]+/, ""); print "  " $0
    }
  '
}

# ── RAM ───────────────────────────────────────────────────────────────────
hwinfo_ram() {
  _hwinfo_header "💾  PAMIĘĆ RAM"

  local total_gb
  total_gb=$(awk '/MemTotal/ {printf "%.1f GiB", $2/1024/1024}' /proc/meminfo)
  echo "  Łącznie zainstalowane: ${C_BOLD}${total_gb}${C_NC}"
  echo

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

# ── KARTA GRAFICZNA ───────────────────────────────────────────────────────
hwinfo_gpu() {
  _hwinfo_header "🎮  KARTA GRAFICZNA"

  echo "  ${C_BOLD}lspci:${C_NC}"
  lspci | grep -iE "VGA|3D|Display" | sed 's/^/    /'

  echo
  if command -v nvidia-smi &>/dev/null; then
    echo "  ${C_BOLD}NVIDIA (nvidia-smi):${C_NC}"
    nvidia-smi --query-gpu=name,driver_version,memory.total,temperature.gpu \
               --format=csv,noheader | \
      awk -F',' '{
        printf "    Model   : %s\n    Driver  : %s\n    VRAM    : %s\n    Temp    : %s\n", \
               $1, $2, $3, $4
      }'

  elif command -v rocm-smi &>/dev/null; then
    echo "  ${C_BOLD}AMD (rocm-smi):${C_NC}"
    rocm-smi --showproductname --showmeminfo vram 2>/dev/null | sed 's/^/    /'

  else
    echo "  ${C_BOLD}Szczegóły (dmidecode):${C_NC}"
    dmidecode -t display 2>/dev/null | awk '
      /^[[:space:]]*(Manufacturer|Product Name|Description|Current Video Mode):/ {
        sub(/^[[:space:]]+/, ""); print "    " $0
      }
    '
  fi
}

# ── MAIN ──────────────────────────────────────────────────────────────────
hwinfo() {
  echo "${C_BOLD}hwinfo${C_NC} – zrzut konfiguracji sprzętowej  $(date '+%Y-%m-%d %H:%M:%S')"
  _hwinfo_check_deps || return 1
  hwinfo_cpu
  hwinfo_motherboard
  hwinfo_ram
  hwinfo_gpu
  echo
  echo "${C_CYAN}══════════════════════════════════════${C_NC}"
  echo
}

export -f _hwinfo_header _hwinfo_check_deps hwinfo_cpu hwinfo_motherboard hwinfo_ram hwinfo_gpu hwinfo
