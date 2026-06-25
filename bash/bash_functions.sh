#!/usr/bin/env bash

##
# Usage/help function for the entire script
##
function bash_customs_usage() {
    cat <<EOF
Usage: source this script or call its functions directly in your shell.

Available functions:

  [Powłoka]
  source_if_exists FILE        – sourcuje FILE.sh z \$BASH_CONFIGURATION_DIR jeśli istnieje
  supports_colors              – sprawdza czy terminal obsługuje kolory

  [Procesy i system]
  make_me_sudo                 – ustawia \$SUDO='sudo' (lub '' gdy root)
  unmake_me_sudo               – cofa make_me_sudo
  exterminatus PATTERN         – zabija procesy pasujące do PATTERN
  reswap                       – wyłącza i włącza swap (czyści pamięć swap)
  who_use_swap                 – lista procesów używających swap
  who_use_port PORT            – lista procesów używających podany port

  [Logowanie]
  log_message LEVEL MSG        – log z poziomem: debug, info, warn, error, man
  log_debug MSG                – log poziom debug
  log_info MSG                 – log poziom info
  log_warn MSG                 – log poziom warn
  log_error MSG                – log poziom error + stack trace
  log_man MSG                  – log poziom man (dokumentacja/pomoc)
  print_stack_trace            – drukuje bieżący stack trace

  [Interakcja]
  are_you_sure                 – pyta o potwierdzenie (Y/N), zwraca kod wyjścia
  yes_or_no PROMPT             – pyta o Y/N, zwraca 0/1

  [Docker]
  check_container_status NAME  – sprawdza status kontenera
  check_compose_status         – sprawdza status usług docker compose
  check_all_services_healthy   – sprawdza czy wszystkie usługi są healthy
  start_compose_services       – startuje usługi docker compose

  [Tekst]
  to_ascii STR                 – konwertuje znaki diakrytyczne na ASCII
  to_kebab_case STR            – konwertuje string do kebab-case
  to_dot_case STR              – konwertuje string do dot.case
  remove_special STR           – usuwa znaki specjalne ze stringa

  [Obrazy]
  heif_to_png                  – konwertuje *.heic w bieżącym katalogu do PNG
  resize_png FILE WIDTH        – skaluje PNG w miejscu
  resize_jpg FILE WIDTH        – skaluje JPG w miejscu

  [Narzędzia]
  weather                      – aktualna pogoda (wttr.in)
  start_x                      – uruchamia środowisko graficzne
  generate_month_dirs          – tworzy strukturę katalogów miesięcznych
  get_and_build                – git pull + wykryj system budowania + zbuduj (gab)
  git_context                  – interaktywne przełączanie kontekstu git (user/email)
  netconf_diag                 – diagnostyka sieci
  dżepetto -p PROMPT           – zapytanie do OpenAI ChatGPT
  update_asdf                  – sprawdza i instaluje nową wersję asdf jeśli dostępna
  reload_config                – przeładowuje konfigurację powłoki z MAIN_CONFIGURATION_DIR/main.sh

  [Java]
  turn_async_profiler_on       – ustawia flagi jądra dla async-profilera JVM
  turn_async_profiler_off      – cofa flagi async-profilera

EOF
}

# Helper function for error logging
function __log_or_echo_error() {
    local message="$1"
    if declare -F log_error &>/dev/null; then
        log_error "$message"
    else
        echo "${C_RED}ERROR: $message${C_NC}" >&2
    fi
}


##
# Sources a file from a specified directory or $BASH_CONFIGURATION_DIR if it exists
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
        log_warn "Neither directory parameter nor \$BASH_CONFIGURATION_DIR is set. Cannot source files reliably."
        return 1
    fi

    local filepath="${directory}/${filename}.sh"
    if [ -f "$filepath" ]; then
        # shellcheck source=/dev/null
        . "$filepath"
    else
        log_warn "File '${filename}.sh' does not exist in '${directory}'"
    fi
}

# Source all files from the specified directory in alphabetical order
# Usage: source_directory <directory_path>
function source_directory() {
  local dir="$1"

  [[ -z "$dir" ]] && {
    __log_or_echo_error "Directory path required"
    return 1
  }

  [[ ! -d "$dir" ]] && {
    __log_or_echo_error "Directory not found: $dir"
    return 1
  }

  local file
  for file in "$dir"/[0-9][0-9][0-9]_*.sh; do
    [[ ! -f "$file" ]] && continue
    source "$file" || {
      __log_or_echo_error "Failed to source: $file"
    }
  done
}

##
# Prints the current git branch (if in a git repo)
# used to calculate PS1 value do not export. Use git_current_branch instead
##
function parse_git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

function check_workspace() {
  ENV_DIRS=(WORKSPACE WORKSPACE_TOOLS SERVICES_DATA POSTGRES_DATA NGINX_DATA)
  ENV_VARS=(DOCKER_COMPOSE)

  for name in "${ENV_DIRS[@]}"; do
    if [ -z "${!name}" ]; then
      log_warn "Var $name is not set"
    elif [ ! -d "${!name}" ]; then
      log_warn "Directory ${!name} doesn't exist"
      mkdir -p "${!name}"
    fi
  done

  for name in "${ENV_VARS[@]}"; do
    if [ -z "${!name}" ]; then
      log_warn "Var $name is not set"
    fi
  done

}

function update_asdf() {
    local asdf_bin="$HOME/.local/bin/asdf"

    if [ ! -x "$asdf_bin" ]; then
        log_error "asdf nie jest zainstalowany w $HOME/.local/bin/asdf"
        return 1
    fi

    local current_version latest_tag
    current_version=$("$asdf_bin" version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    latest_tag=$(curl -sf https://api.github.com/repos/asdf-vm/asdf/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$latest_tag" ]; then
        log_error "Nie udało się pobrać informacji o najnowszej wersji asdf"
        return 1
    fi

    if [ "$current_version" = "$latest_tag" ]; then
        log_info "asdf jest aktualne ($current_version)"
        return 0
    fi

    log_info "Aktualizacja asdf: $current_version → $latest_tag"
    local _os _arch
    _os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    _arch="$(uname -m)"
    [[ "$_arch" == "x86_64" ]] && _arch="amd64"
    [[ "$_arch" == "arm64" || "$_arch" == "aarch64" ]] && _arch="arm64"
    local archive="asdf-${latest_tag}-${_os}-${_arch}.tar.gz"
    local download_url="https://github.com/asdf-vm/asdf/releases/download/${latest_tag}/${archive}"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    set +e
    curl -L "$download_url" -o "$tmp_dir/$archive"
    local curl_status=$?
    set -e

    if [ $curl_status -ne 0 ]; then
        log_error "Nie udało się pobrać asdf $latest_tag"
        rm -rf "$tmp_dir"
        return 1
    fi

    tar -xzf "$tmp_dir/$archive" -C "$tmp_dir"
    cp "$tmp_dir/asdf" "$asdf_bin"
    chmod +x "$asdf_bin"
    rm -rf "$tmp_dir"

    log_info "asdf zaktualizowany do $latest_tag"
}

source_directory "$BASH_CONFIGURATION_DIR/functions.d/"

##
# Reloads shell configuration from MAIN_CONFIGURATION_DIR/main.sh
##
function reload_config() {
    if [ -z "$MAIN_CONFIGURATION_DIR" ]; then
        log_error "MAIN_CONFIGURATION_DIR is not set — cannot reload"
        return 1
    fi

    local main_script="$MAIN_CONFIGURATION_DIR/main.sh"
    if [ ! -f "$main_script" ]; then
        log_error "main.sh not found: $main_script"
        return 1
    fi

    # Unset BASH_FUNCTIONS_LOADED so bash/main.sh guard allows full re-initialization
    unset BASH_FUNCTIONS_LOADED

    # Ensure bash/main.sh doesn't short-circuit on inherited SUPPRESS_SOURCING=1
    export SUPPRESS_SOURCING=0

    # shellcheck source=/dev/null
    . "$main_script" || {
        log_error "Błąd podczas ładowania $main_script"
        return 1
    }
    log_info "Konfiguracja przeładowana z $main_script"
}

##
# Export unexported „by default" functions so they remain available after 'source'
##
export -f bash_customs_usage
export -f supports_colors
export -f update_asdf
export -f reload_config

# DONE we don't need sourcing anymore
export BASH_FUNCTIONS_LOADED=1