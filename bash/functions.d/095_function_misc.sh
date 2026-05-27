#!/usr/bin/env bash

function install_lib() {
  local _args=("$@") _t="" _e="" _x=false _i
  for (( _i = 0; _i < ${#_args[@]}; _i++ )); do
    case "${_args[_i]}" in
      -t) _t="${_args[_i+1]}"; _i=$(( _i + 1 )) ;;
      -e) _e="${_args[_i+1]}"; _i=$(( _i + 1 )) ;;
      -x) _x=true ;;
    esac
  done
  if [[ -n "$_t" && -d "$WORKSPACE_TOOLS/$_t" ]]; then
    [[ "$_x" == true && -n "$_e" ]] && . "$WORKSPACE_TOOLS/$_t/$_e"
    return 0
  fi

  local OPTIND opt
  local repo_url=""
  local target_dir=""
  local exec_file=""
  local exp=false

  function _install_lib_show_help {
    cat <<EOF
Użycie: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>] [-x] [-h]
  -r: Adres repozytorium
  -t: Opcjonalny katalog docelowy
  -e: Opcjonalny plik wykonywalny
  -x: Uruchamia sourcing pliku wskazanego w -e
  -h: Wyświetl pomoc
EOF
  }

  function _install_lib_source {
    if [[ $exp == true ]]; then
      . "$target_dir/$exec_file"
    fi
  }

  while getopts ":hr:t:e:x" opt; do
    case "$opt" in
    h)
      _install_lib_show_help
      return 0
      ;;
    r) repo_url="$OPTARG" ;;   # Adres repozytorium
    t) target_dir="$OPTARG" ;; # Opcjonalny katalog docelowy
    e) exec_file="$OPTARG" ;;  # Opcjonalny plik wykonywalny
    x) exp=true ;;
    *)
      log_warn "Nieznana opcja: -$OPTARG"
      log_man "Użycie: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>] [-x] [-h]"
      return 1
      ;;
    esac
  done

  if [ -z "$repo_url" ]; then
    log_error "Adres repozytorium (-r) jest obowiązkowy."
    log_man "Użycie: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>] [-x] [-h]"
    return 1
  fi

  if [ -n "$target_dir" ]; then
    target_dir="$WORKSPACE_TOOLS/$target_dir"
  else
    target_dir="$WORKSPACE_TOOLS/$(basename "$repo_url" .git)"
  fi

  if [ -d "$target_dir" ]; then
    _install_lib_source
    return 0
  fi

  if ! git clone "$repo_url" "$target_dir"; then
    log_error "Nie udało się sklonować repozytorium '$repo_url'."
    return 1
  fi

  if [ -n "$exec_file" ]; then
    if [ ! -x "$target_dir/$exec_file" ]; then
      chmod +x "$target_dir/$exec_file"
    fi
  fi

  _install_lib_source

  local OPTIND=1 # reset param pointer
}

function weather() {
  if [[ -z "$1" ]]; then
    log_man "Usage: get_weather <city_name>"
    return 1
  fi

  local city_name="$1"
  local response
  response=$(curl -s "wttr.in/${city_name}?format=%C+%t+%h+%w")

  if [[ -z "$response" ]]; then
    log_error "Unable to fetch weather for ${city_name}."
    return 1
  fi

  local weather_desc
  weather_desc=$(echo "$response" | awk '{print $1}')
  local temperature
  temperature=$(echo "$response" | awk '{print $2}')
  local humidity
  humidity=$(echo "$response" | awk '{print $3}')
  local wind_speed
  wind_speed=$(echo "$response" | awk '{print $4, $5}')

  echo "----------------------------------------"
  echo "| Weather in ${city_name}                   |"
  echo "----------------------------------------"
  printf "| %-15s | %-10s |\n" "Temperature" "${temperature}"
  printf "| %-15s | %-10s |\n" "Humidity" "${humidity}"
  printf "| %-15s | %-10s |\n" "Description" "${weather_desc}"
  printf "| %-15s | %-10s |\n" "Wind Speed" "${wind_speed}"
  echo "----------------------------------------"
}
function start_x() {
  make_me_sudo
  $SUDO systemctl start lightdm
  unmake_me_sudo
}

function generate_month_dirs() {
  local months=("styczen" "luty" "marzec" "kwiecien" "maj" "czerwiec" "lipiec" "sierpien" "wrzesien" "pazdziernik" "listopad" "grudzien")
  local i

  for i in {1..12}; do
    local dir_name
    dir_name=$(printf "%02d-%s" "$i" "${months[$((i - 1))]}")

    if [ -d "$dir_name" ]; then
      log_warn "Directory '$dir_name' already exists, skipping..."
    else
      mkdir "$dir_name"
      log_info "Created directory: $dir_name"
    fi
  done
}

function tmux_dump() {
  local out="${1:-tmux-session-dump-$(date +%Y%m%d-%H%M%S).txt}"

  if ! command -v tmux >/dev/null 2>&1; then
    echo "tmux is not installed" >&2
    return 1
  fi

  if [ -z "${TMUX:-}" ]; then
    echo "Not running inside tmux session" >&2
    return 1
  fi

  {
    echo "TMUX SESSION DUMP"
    echo "Generated: $(date -Is)"
    echo

    echo "=== CURRENT SESSION ==="
    tmux display-message -p \
      'session=#{session_name} id=#{session_id} windows=#{session_windows} attached=#{session_attached}'
    echo

    echo "=== SESSIONS ==="
    tmux list-sessions -F \
      'session=#{session_name} id=#{session_id} windows=#{session_windows} attached=#{session_attached}'
    echo

    echo "=== WINDOWS ==="
    tmux list-windows -a -F \
      'session=#{session_name} window=#{window_index} name=#{window_name} active=#{window_active} panes=#{window_panes} layout=#{window_layout}'
    echo

    echo "=== PANES ==="
    tmux list-panes -a -F \
      'session=#{session_name} window=#{window_index} pane=#{pane_index} id=#{pane_id} active=#{pane_active} size=#{pane_width}x#{pane_height} path=#{pane_current_path} command=#{pane_current_command} title=#{pane_title}'
    echo

    echo "=== GLOBAL OPTIONS ==="
    tmux show-options -g
    echo

    echo "=== GLOBAL WINDOW OPTIONS ==="
    tmux show-window-options -g

  } > "$out"

  echo "$out"
}

export -f start_x
export -f weather
export -f generate_month_dirs
export -f tmux_dump
