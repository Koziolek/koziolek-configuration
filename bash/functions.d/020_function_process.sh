#!/usr/bin/env bash

##
# Sets up environment variables to use sudo if not already root
##
function make_me_sudo() {
  export SUDO=''
  export RESET_SUDO=0
  if ((EUID != 0)); then
    SUDO='sudo'
    RESET_SUDO=1
  fi
  return 0
}

##
# Revokes sudo privileges set by make_me_sudo
##
function unmake_me_sudo() {
  if ((RESET_SUDO != 0)); then
    $SUDO -K
  fi
  unset SUDO
  unset RESET_SUDO
}

##
# Kills processes matching a given pattern
# Usage: exterminatus PATTERN
# (Same as order66)
##
function exterminatus() {
  if [ $# -lt 1 ]; then
    log_man "Usage: exterminatus PATTERN"
    return 1
  fi
  local pattern="$1"
  # Use pgrep to avoid killing the grep process itself
  pgrep -f "$pattern" | xargs -r kill -9
}

##
# List processes that use given PORT if --sudo is set then run it as sudo.
##
function who_use_port() {
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

export -f exterminatus
export -f who_use_port
export -f make_me_sudo
export -f unmake_me_sudo
