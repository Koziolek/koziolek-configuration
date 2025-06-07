#!/usr/bin/env bash

##
# Usage/help function for the entire script
##
function bash_customs_usage() {
    cat <<EOF
Usage: source this script or call its functions directly in your shell.

Available functions:

  1) source_if_exists FILE
       - Sources FILE.sh from \$BASH_CONFIGURATION_DIR if it exists.

  2) parse_git_branch
       - Prints the current git branch (if in a git repo).

  3) make_me_sudo
       - Sets up environment variables to use sudo without a password prompt
         (if not already root).

  4) unmake_me_sudo
       - Revokes sudo privileges set by make_me_sudo.

  5) order66 PATTERN
       - Kills processes matching PATTERN.

  6) exterminatus PATTERN
       - Kills processes matching PATTERN (same as order66, different universe).

  7) heif_to_png
       - Converts all *.heic files in the current directory to PNGs using heif-convert.

  8) who_use_port
       - List processes that use given port.

  9) weather
       - Current weather

  10) turn_async_profiler_on/turn_async_profiler_off
       - Change kernel flags for java async profiler

  11) supports_colors
       - Check if you could use colors in terminal

  12) log_message [level] [messages]
       - Log messages on given level. If level is not in: debug, info, error, man then use no_level

  13) are_you_sure
       – Ask user Yes/No

Additional notes:
  - Ensure \$BASH_CONFIGURATION_DIR is set to the directory containing your
    configuration files and the "logo-ascii-art.txt" for print_logo.
  - Some functions require extra tools to be installed (e.g., neofetch,
    heif-convert, xdotool, tmux).

EOF
}

##
# Sources a file from specified directory or $BASH_CONFIGURATION_DIR if it exists
# Usage: source_if_exists filename [directory]
##
function source_if_exists() {
    if [ $# -lt 1 ]; then
        log_man "Usage: source_if_exists FILE [DIRECTORY]"
        return 1
    fi

    local filename="$1"
    local directory="${2:-$BASH_CONFIGURATION_DIR}"

    if [ -z "$directory" ]; then
        echo "Warning: Neither directory parameter nor \$BASH_CONFIGURATION_DIR is set. Cannot source files reliably."
        return 1
    fi

    local filepath="${directory}/${filename}.sh"
    if [ -f "$filepath" ]; then
        # shellcheck source=/dev/null
        . "$filepath"
    else
        echo "File '${filename}.sh' does not exist in '${directory}'"
    fi
}

##
# Prints the current git branch (if in a git repo)
##
function parse_git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

##
# Sets up environment variables to use sudo if not already root
##
function make_me_sudo () {
    export SUDO=''
    export RESET_SUDO=0
    if (( EUID != 0 )); then
       SUDO='sudo'
       RESET_SUDO=1
    fi
    return 0
}

##
# Revokes sudo privileges set by make_me_sudo
##
function unmake_me_sudo () {
    if (( RESET_SUDO != 0 )); then
        $SUDO -K
    fi
    unset SUDO
    unset RESET_SUDO
}

##
# Kills processes matching a given pattern
# Usage: order66 PATTERN
##
function order66 () {
    if [ $# -lt 1 ]; then
        echo "Usage: order66 PATTERN"
        return 1
    fi
    exterminatus "$@"
}

##
# Kills processes matching a given pattern
# Usage: exterminatus PATTERN
# (Same as order66)
##
function exterminatus () {
    if [ $# -lt 1 ]; then
        echo "Usage: exterminatus PATTERN"
        return 1
    fi
    local pattern="$1"
    # Use pgrep to avoid killing the grep process itself
    pgrep -f "$pattern" | xargs -r kill -9
}

##
# Converts all *.heic files in the current directory to PNGs
# Requires heif-convert
##
function heif_to_png () {
    if ! command -v heif-convert >/dev/null 2>&1; then
        echo "Error: 'heif-convert' is not installed or not found in PATH."
        return 1
    fi

    local count=0
    for i in *.heic; do
        # If no *.heic files exist, stop
        [ -e "$i" ] || { echo "No .heic files found."; return 0; }

        heif-convert "$i" "$(basename -s .heic "$i").png"
        ((count++))
    done
    echo "Converted $count file(s) from .heic to .png."
}

##
# Resizes the currently active window to full screen if running under X11
# and using xdotool ow gdbus ir swaymsg on Wayland
##
function resize_to_full () {
    # Only run if X11 session
    if [ "$XDG_SESSION_TYPE" = "x11" ]; then
        # Check if xdotool is installed
        if ! command -v xdotool >/dev/null 2>&1; then
            return 0
        fi

        local win_id
        win_id="$(xdotool getactivewindow)"

	if [ -z "$win_id" ]; then 
	    echo "No active window found"
	    return 0
	fi    

        local current_width
        current_width="$(xwininfo -id "$win_id" -stats \
                          | grep -E '(Width):' \
                          | awk '{print $2}')"
        local current_height
        current_height="$(xwininfo -id "$win_id" -stats \
                          | grep -E '(Height):' \
                          | awk '{print $2}')"

        local max_size

        readarray -t max_size < <(xrandr | grep -E '\*' | awk '{print $1}')

        local is_max=0
        for res in "${max_size[@]}" ; do
          local max_width
          local max_height
          IFS='x' read -r max_width max_height <<< "$res"
          if [[ ("$current_width" == "$max_width" &&  "$current_height" == "$max_height")
            || ("$current_width" == "$max_height" &&  "$current_height" == "$max_width") ]]; then
               is_max=1
               break
          fi
        done

        if [[ $is_max -eq 0 ]]; then
             xdotool key F11
        fi
    elif [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        # --- GNOME ---
        if command -v gdbus >/dev/null 2>&1; then
            echo "Attempting to toggle fullscreen in GNOME"
            gdbus call --session \
              --dest org.gnome.Shell \
              --object-path /org/gnome/Shell \
              --method org.gnome.Shell.Eval \
              'global.display.focus_window.toggle_fullscreen();' \
              >/dev/null 2>&1
            return $?
        fi

        # --- sway / wlroots-based compositor ---
        if command -v swaymsg >/dev/null 2>&1; then
            echo "Attempting to toggle fullscreen in Sway"
            swaymsg fullscreen toggle
            return $?
        fi

        echo "Wayland session detected, but no supported window manager interface found (gdbus/swaymsg missing)"
        return 0
    else
        echo "Unsupported session type: $XDG_SESSION_TYPE"
        return 0
    fi 
}

##
# Runs tmux if not inside a tmux session already
##
function run_tmux () {
    if command -v tmux >/dev/null 2>&1; then
        # If not in a tmux session and not in a TERM that starts with "screen"
        if [[ ! "$TERM" =~ screen ]] && [ -z "$TMUX" ]; then
            exec tmux
        fi
    fi
}

##
# Prints an ASCII art logo using neofetch
# Expects $BASH_CONFIGURATION_DIR/logo-ascii-art.txt to exist
##
function print_logo () {
    if ! command -v neofetch >/dev/null 2>&1; then
        echo "Error: 'neofetch' is not installed or not found in PATH."
        return 1
    fi

    if [ -z "$BASH_CONFIGURATION_DIR" ] || [ ! -f "$BASH_CONFIGURATION_DIR/logo-ascii-art.txt" ]; then
        echo "Error: logo-ascii-art.txt not found in \$BASH_CONFIGURATION_DIR."
        return 1
    fi

    neofetch --ascii "$BASH_CONFIGURATION_DIR/logo-ascii-art.txt"
}

##
# List processes that use given PORT if --sudo is set then run it as sudo.
##
function who_use_port () {
    if [ $# -lt 1 ]; then
        log_man "Usage: who_use_port [--sudo] PORT"
        return 1
    fi

    local root_mode=false
    local port

    # Check if the first argument is --sudo
    if [ "$1" == "--sudo" ]; then
        root_mode=true
        shift # Remove the --sudo argument
    fi

    port="$1"

    if [ -z "$port" ]; then
        echo "Usage: who_use_port [--sudo] PORT"
        return 1
    fi

    if $root_mode; then
        make_me_sudo
    fi

    # Use pgrep to avoid killing the grep process itself
    $SUDO netstat -tulpn | grep "$port" | awk '!seen[$0]++'

    if $root_mode; then
        unmake_me_sudo
    fi
}

function to_kebab_case() {
  local input="$1"
  echo "$input" | tr '[:upper:]' '[:lower:]' | sed -e 's/ /-/g' -e 's/^-//' -e 's/-$//'
}

function check_workspace() {
  if [ ! -d "$WORKSPACE" ]; then
    mkdir -p "$WORKSPACE";
  fi
  if [ ! -d "$WORKSPACE_TOOLS" ]; then
    mkdir -p "WORKSPACE_TOOLS";
  fi
}

function install_lib() {
  local repo_url=""
  local target_dir=""
  local exec_file=""

  while getopts ":r:t:e:" opt; do
    case "$opt" in
      r) repo_url="$OPTARG" ;; # Adres repozytorium
      t) target_dir="$OPTARG" ;; # Opcjonalny katalog docelowy
      e) exec_file="$OPTARG" ;; # Opcjonalny plik wykonywalny
      *)
        echo "Nieznana opcja: -$OPTARG"
        echo "Użycie: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>]"
        return 1
        ;;
    esac
  done

  if [ -z "$repo_url" ]; then
    log_error "Adres repozytorium (-r) jest obowiązkowy."
    echo "Użycie: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>]"
    return 1
  fi

  if [ -n "$target_dir" ]; then
    target_dir="$WORKSPACE_TOOLS/$target_dir"
  else
    target_dir="$WORKSPACE_TOOLS/$(basename "$repo_url" .git)"
  fi

  if [ -d "$target_dir" ]; then
    return 0
  fi

  if ! git clone "$repo_url" "$target_dir"; then
    log_error "Nie udało się sklonować repozytorium '$repo_url'."
    return 1
  fi

  if [ -n "$exec_file" ]; then
    if [ ! -x "$target_dir/$exec_file" ]; then
      chmod +x "$exec_file"
    fi
  fi
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

function resize_png() {
    # Argumenty: $1 - nazwa pliku, $2 - skala w procentach
    local scale=${2:-50}  # Skala domyślna to 50% (jeśli brak podano)

    # Sprawdź, czy podano poprawną wartość skali (liczby całkowite)
    if ! [[ "$scale" =~ ^[0-9]+$ ]] || [ "$scale" -le 0 ] || [ "$scale" -gt 100 ]; then
        log_error "Skala musi być liczbą całkowitą z zakresu 1-100."
        return 1
    fi

    # Jeśli podano nazwę pliku
    if [ -n "$1" ]; then
        # Sprawdź, czy plik istnieje i jest plikiem PNG
        if [ -f "$1" ] && [[ "$1" == *.png ]]; then
            log_info "Przetwarzanie pliku: $1 (skala: ${scale}%)"
            convert "$1" -resize "${scale}%" "$1"
        else
            log_error "Plik '$1' nie istnieje lub nie jest plikiem PNG."
            return 1
        fi
    else
        # Jeśli nie podano nazwy pliku, przetwarzaj wszystkie pliki PNG w katalogu
        log_info "Przetwarzanie wszystkich plików PNG w bieżącym katalogu (skala: ${scale}%)"
        for file in *.png; do
            if [ -f "$file" ]; then
                log_info "Przetwarzanie pliku: $file"
                convert "$file" -resize "${scale}%" "$file"
            fi
        done
    fi

    echo "Przetwarzanie zakończone."
}

function turn_async_profiler_on() {
  make_me_sudo
  $SUDO sh -c 'echo 1 > /proc/sys/kernel/perf_event_paranoid'
  $SUDO sh -c 'echo 0 > /proc/sys/kernel/kptr_restrict'
  unmake_me_sudo
}

function turn_async_profiler_off() {
  make_me_sudo
  $SUDO sh -c 'echo 4 > /proc/sys/kernel/perf_event_paranoid'
  $SUDO sh -c 'echo 1 > /proc/sys/kernel/kptr_restrict'
  unmake_me_sudo
}

function supports_colors() {
    # Sprawdzenie czy terminal obsługuje kolory
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
        local colors=$(tput colors 2>/dev/null)
        [[ $colors -ge 8 ]]
    else
        return 1
    fi
}

function set_dirtrim_by_path_length() {
    local full_path="$PWD"
    local display_path="${full_path/#$HOME/~}"
    if [ "${#display_path}" -gt 20 ]; then
        export PROMPT_DIRTRIM=1
    else
        export PROMPT_DIRTRIM=3
    fi
}

log_message() {
    local level="$1"
    shift
    local messages=("$@")

    local prefix=""
    case "$level" in
        "debug")
            prefix="${C_BLUE}${level^^}: ${C_NC}"
            ;;
        "info")
            prefix="${C_GREEN}${level^^}: ${C_NC}"
            ;;
        "warn")
            prefix="${C_ORANGE}${level^^}: ${C_NC}"
            ;;
        "error")
            prefix="${C_RED}${level^^}: ${C_NC}"
            ;;
        "man")
            prefix="${C_NC}"
            ;;
        *)
            prefix="${C_NC}${level^^} "
            ;;
    esac
    echo -e "${prefix}${messages[*]}${C_NC}"
}

function log_debug() {
    log_message "debug" "$@"
}

function log_info() {
    log_message "info" "$@"
}

function log_warn() {
    log_message "warn" "$@"
}
function log_error() {
    log_message "error" "$@"
}

function log_man() {
    log_message "man" "$@"
}

function yes_or_no(){
    local default=${1:-"n"}
    local response
    local valid=false

    while ! $valid; do
        if [ "$default" = "y" ]; then
            read -r -p "${C_GREEN}[Y/n]:${C_NC} " response
        else
            read -r -p "${C_RED}[y/N]:${C_NC} " response
        fi

        response=${response:-$default}
        case ${response,,} in
            y|yes|Y|Yes)
                valid=true
                ;;
            n|no|N|No)
                valid=true
                ;;
            *)
                log_man "Please answer with 'y' or 'n'"
                ;;
        esac
    done
    echo "${response}"
}


function are_you_sure(){
    local default=${1:-"n"}
    local response
    local valid=false

    while ! $valid; do
        if [ "$default" = "y" ]; then
            read -r -p "${C_GREEN}Are you sure? [Y/n]:${C_NC} " response
        else
            read -r -p "${C_RED}Are you sure? [y/N]:${C_NC} " response
        fi

        response=${response:-$default}
        case ${response,,} in
            y|yes|Y|Yes)
                valid=true
                ;;
            n|no|N|No)
                valid=true
                ;;
            *)
                log_man "Please answer with 'y' or 'n'"
                ;;
        esac
    done
    echo "${response}"
}

##
# Export functions so they remain available after 'source'
##
export -f bash_customs_usage
export -f parse_git_branch
export -f make_me_sudo
export -f unmake_me_sudo
export -f order66
export -f exterminatus
export -f heif_to_png
export -f who_use_port
export -f weather
export -f resize_png
export -f turn_async_profiler_on
export -f turn_async_profiler_off
export -f supports_colors
export -f log_message
export -f log_debug
export -f log_info
export -f log_warn
export -f log_error
export -f log_man
export -f are_you_sure
export -f yes_or_no
