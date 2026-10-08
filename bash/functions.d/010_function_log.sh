#!/usr/bin/env bash

# Komunikaty z tablic MSG_* (005_function_messages.sh) — doładuj, gdy ten plik sourcowany osobno (np. w testach).
# Bez dirname: plik bywa sourcowany przy pustym/okrojonym PATH.
if ! declare -F messages_ensure_loaded >/dev/null; then
  _log_src="${BASH_SOURCE[0]}"
  [[ "$_log_src" == */* ]] || _log_src="./$_log_src"
  . "${_log_src%/*}/005_function_messages.sh"
  unset _log_src
fi

# Log a message with specified log level and color formatting
# Usage: log_message <level> <message...>
#
# Parameters:
#   level    - Log level (debug|info|warn|error|man). Determines message prefix and color
#   message  - One or more message strings to output
#
# Example:
#   log_message "info" "Starting process" "with parameters"
function log_message() {
  local level="$1"
  shift
  local messages=("$@")

  if [ -z "$level" ] || [ ${#messages[@]} -eq 0 ]; then
    echo "${C_RED}NOTHING TO LOG${C_NC}: Empty log call at ${FUNCNAME[*]}"
    return 0;
  fi

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

# Funkcje log_<poziom>: pierwszy argument będący kluczem z własnej tablicy MSG_<POZIOM> jest szablonem
# (reszta argumentów = wartości placeholderów); inny pierwszy argument to dosłowny tekst jak dotąd.
# Do log_message trafia zawsze gotowy komunikat.
# Usage: log_info <klucz> [wartości...]   |   log_info <tekst...>
function log_debug() {
  messages_ensure_loaded
  if [[ -n "${1:-}" && -n "${MSG_DEBUG[$1]+x}" ]]; then
    local _tpl="${MSG_DEBUG[$1]}" _msg
    shift
    printf -v _msg -- "$_tpl" "$@"
    log_message "debug" "$_msg"
  else
    log_message "debug" "$@"
  fi
}

function log_info() {
  messages_ensure_loaded
  if [[ -n "${1:-}" && -n "${MSG_INFO[$1]+x}" ]]; then
    local _tpl="${MSG_INFO[$1]}" _msg
    shift
    printf -v _msg -- "$_tpl" "$@"
    log_message "info" "$_msg"
  else
    log_message "info" "$@"
  fi
}

function log_warn() {
  messages_ensure_loaded
  if [[ -n "${1:-}" && -n "${MSG_WARN[$1]+x}" ]]; then
    local _tpl="${MSG_WARN[$1]}" _msg
    shift
    printf -v _msg -- "$_tpl" "$@"
    log_message "warn" "$_msg"
  else
    log_message "warn" "$@"
  fi
}

function log_error() {
  messages_ensure_loaded
  if [[ -n "${1:-}" && -n "${MSG_ERROR[$1]+x}" ]]; then
    local _tpl="${MSG_ERROR[$1]}" _msg
    shift
    printf -v _msg -- "$_tpl" "$@"
    log_message "error" "$_msg"
  else
    log_message "error" "$@"
  fi
  print_stack_trace
}

function log_man() {
  messages_ensure_loaded
  if [[ -n "${1:-}" && -n "${MSG_MAN[$1]+x}" ]]; then
    local _tpl="${MSG_MAN[$1]}" _msg
    shift
    printf -v _msg -- "$_tpl" "$@"
    log_message "man" "$_msg"
  else
    log_message "man" "$@"
  fi
}

function print_stack_trace() {
    local frame=0
    echo "Stack trace:"
    while [[ ${FUNCNAME[frame]} ]]; do
        echo "  ${frame}: ${FUNCNAME[frame]}() in ${BASH_SOURCE[frame]}:${BASH_LINENO[frame-1]}"
        ((frame++))
    done
}

function log_exterminatus () {
  local pattern="$1"

  log_man \
    "In fealty to the God-Emperor, our undying Lord,
      and by the grace of the Golden Throne,
      I declare Exterminatus upon the ${pattern}"
}

export -f log_message
export -f log_debug
export -f log_info
export -f log_warn
export -f log_error
export -f log_man
export -f print_stack_trace
