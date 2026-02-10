#!/usr/bin/env bash

# ============================================================================
# get_and_build - Git pull + auto-detect build system + build
# ============================================================================
# System pluginów: każdy plik w katalogu plugins/ definiuje jeden system
# budowania. Plugin to skrypt bashowy eksportujący 3 zmienne:
#   PLUGIN_NAME    - nazwa systemu (np. "maven")
#   PLUGIN_DETECT  - plik/pliki, których obecność oznacza ten system (np. "pom.xml")
#   PLUGIN_CMD     - polecenie budowania (np. "mvn clean verify")
#
# Pluginy ładowane są alfabetycznie. Pierwszy pasujący wygrywa.
# Aby dodać nowy system budowania, wystarczy wrzucić plik do plugins/.
# ============================================================================

function get_and_build() {
  _gab_usage() {
    cat <<EOF
${C_BOLD}get_and_build${C_NC} - pull + wykryj system budowania + zbuduj

${C_BOLD}Użycie:${C_NC}
    get_and_build [opcje] [katalog]

${C_BOLD}Opcje:${C_NC}
    -s, --skip-pull     Pomiń git pull
    -d, --dry-run       Tylko wykryj system, nie buduj
    -l, --list          Wylistuj dostępne pluginy
    -p, --plugin DIR    Użyj alternatywnego katalogu pluginów
    -h, --help          Pokaż tę pomoc

${C_BOLD}Przykład dodania nowego systemu budowania:${C_NC}
    Stwórz plik plugins/50-sbt.sh:
        PLUGIN_NAME="sbt"
        PLUGIN_DETECT="build.sbt"
        PLUGIN_CMD="sbt clean test"
EOF
  }

  _gab_load_plugins() {
    local plugins_dir="$1"

    if [[ ! -d "$plugins_dir" ]]; then
      log_error "Katalog pluginów nie istnieje: ${plugins_dir}"
      return 1
    fi

    local count=0
    for plugin_file in "${plugins_dir}"/*.sh; do
      [[ -f "$plugin_file" ]] || continue

      PLUGIN_NAME=""
      PLUGIN_DETECT=""
      PLUGIN_CMD=""

      # shellcheck source=/dev/null
      source "$plugin_file"

      if [[ -z "$PLUGIN_NAME" || -z "$PLUGIN_DETECT" || -z "$PLUGIN_CMD" ]]; then
        log_warn "Plugin $(basename "$plugin_file") jest niekompletny, pomijam"
        continue
      fi

      _GAB_LOADED_NAMES+=("$PLUGIN_NAME")
      _GAB_LOADED_DETECTS+=("$PLUGIN_DETECT")
      _GAB_LOADED_CMDS+=("$PLUGIN_CMD")
      count=$((count + 1))
    done

    if [[ $count -eq 0 ]]; then
      log_error "Nie znaleziono żadnych pluginów w ${plugins_dir}"
      return 1
    fi

    log_info "Załadowano ${count} plugin(ów)"
  }

  _gab_list_plugins() {
    local plugins_dir="$1"

    _gab_load_plugins "$plugins_dir" || return 1
    echo ""
    printf "${C_BOLD}Dostępne systemy budowania:${C_NC}\n"
    echo ""
    printf "  ${C_BOLD}%-15s %-25s %s${C_NC}\n" "NAZWA" "WYKRYWANIE" "POLECENIE"
    printf "  %-15s %-25s %s\n" "───────────────" "─────────────────────────" "──────────────────────────────"
    for i in "${!_GAB_LOADED_NAMES[@]}"; do
      printf "  %-15s %-25s %s\n" "${_GAB_LOADED_NAMES[$i]}" "${_GAB_LOADED_DETECTS[$i]}" "${_GAB_LOADED_CMDS[$i]}"
    done
    echo ""
  }

  _gab_detect_build_system() {
    local work_dir="$1"

    for i in "${!_GAB_LOADED_NAMES[@]}"; do
      local detect="${_GAB_LOADED_DETECTS[$i]}"

      IFS='|' read -ra detect_files <<<"$detect"
      for file in "${detect_files[@]}"; do
        file="$(echo "$file" | xargs)"
        if [[ -e "${work_dir}/${file}" ]]; then
          echo "$i"
          return 0
        fi
      done
    done

    return 1
  }

  _gab_do_git_pull() {
    local work_dir="$1"

    if [[ ! -d "${work_dir}/.git" ]]; then
      log_error "Katalog ${work_dir} nie jest repozytorium Git"
      return 1
    fi

    log_info "Wykonuję git pull w ${work_dir}..."
    if git -C "$work_dir" pull; then
      log_info "Git pull zakończony pomyślnie"
    else
      log_error "Git pull nie powiódł się"
      return 1
    fi
  }

  _gab_do_build() {
    local work_dir="$1"
    local idx="$2"

    local name="${_GAB_LOADED_NAMES[$idx]}"
    local cmd="${_GAB_LOADED_CMDS[$idx]}"

    log_info "Wykryto system budowania: ${C_BOLD}${name}${C_NC}"
    log_info "Uruchamiam: ${C_BOLD}${cmd}${C_NC}"
    echo ""

    if (cd "$work_dir" && eval "$cmd"); then
      echo ""
      log_info "Budowanie (${name}) zakończone pomyślnie ✓"
    else
      echo ""
      log_error "Budowanie (${name}) nie powiodło się ✗"
      return 1
    fi
  }

  local _gab_script_dir
  _gab_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local plugins_dir="${_gab_script_dir}/gab_plugins"

  local skip_pull=false
  local dry_run=false
  local do_list=false
  local work_dir="."

  declare -a _GAB_LOADED_NAMES=()
  declare -a _GAB_LOADED_DETECTS=()
  declare -a _GAB_LOADED_CMDS=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -s | --skip-pull)
      skip_pull=true
      shift
      ;;
    -d | --dry-run)
      dry_run=true
      shift
      ;;
    -l | --list)
      do_list=true
      shift
      ;;
    -p | --plugin)
      plugins_dir="$2"
      shift 2
      ;;
    -h | --help)
      _gab_usage
      return 0
      ;;
    -*)
      log_error "Nieznana opcja: $1"
      _gab_usage
      return 1
      ;;
    *)
      work_dir="$1"
      shift
      ;;
    esac
  done

  if $do_list; then
    _gab_list_plugins "$plugins_dir"
    return $?
  fi

  work_dir="$(cd "$work_dir" && pwd)"

  printf "${C_BOLD}═══════════════════════════════════════${C_NC}\n"
  printf "${C_BOLD}  get_and_build${C_NC}\n"
  printf "${C_BOLD}═══════════════════════════════════════${C_NC}\n"
  echo ""

  # 1. Git pull
  if $skip_pull; then
    log_warn "Pomijam git pull (--skip-pull)"
  else
    _gab_do_git_pull "$work_dir" || return 1
  fi

  # 2. Ładowanie pluginów i detekcja
  _gab_load_plugins "$plugins_dir" || return 1

  local detected_idx
  if detected_idx=$(_gab_detect_build_system "$work_dir"); then
    if $dry_run; then
      log_info "Wykryto: ${C_BOLD}${_GAB_LOADED_NAMES[$detected_idx]}${C_NC} (dry-run, nie buduję)"
      return 0
    fi
    # 3. Build
    _gab_do_build "$work_dir" "$detected_idx" || return 1
  else
    log_error "Nie rozpoznano systemu budowania w ${work_dir}"
    log_info "Dostępne systemy:"
    for i in "${!_GAB_LOADED_NAMES[@]}"; do
      echo "  - ${_GAB_LOADED_NAMES[$i]} (szuka: ${_GAB_LOADED_DETECTS[$i]})"
    done
    return 1
  fi
}

export -f get_and_build
