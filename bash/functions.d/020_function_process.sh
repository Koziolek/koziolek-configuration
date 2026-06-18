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
    log_man \
      "Usage
pray to Emperor and then:
  exterminatus PATTERN"
    return 1
  fi

  local root_mode=false
  local pattern

  # Check if the first argument is --sudo
  if [ "$1" == "--sudo" ]; then
    root_mode=true
    shift # Remove the --sudo argument
  fi

  pattern="$1"
  if $root_mode; then
    make_me_sudo
  fi
  log_exterminatus "process of ${pattern}"
  local _pids
  _pids=$(pgrep -f "$pattern")
  if [ -n "$_pids" ]; then
    echo "$_pids" | $SUDO xargs kill -9
  fi

  if $root_mode; then
    unmake_me_sudo
  fi
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

  if [[ "$(uname -s)" == "Darwin" ]]; then
    $SUDO lsof -i ":${port}" -n -P
  else
    $SUDO ss -tulpn | grep "$port" | awk '!seen[$0]++'
  fi

  if $root_mode; then
    unmake_me_sudo
  fi
}

##
# Clear swap by turn it off then on.
##
function reswap() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    log_warn "reswap: swapoff/swapon niedostępne na macOS"
    return 1
  fi
  make_me_sudo

  $SUDO swapoff -a
  $SUDO swapon -a

  unmake_me_sudo
}

##
# Shows who use swap
##
function who_use_swap() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    log_warn "who_use_swap: /proc niedostępny na macOS"
    return 1
  fi
  for pid in /proc/[0-9]*; do
    name=$(awk '/Name/ {print $2}' "$pid/status" 2>/dev/null)
    swap=$(awk '/VmSwap/ {print $2}' "$pid/status" 2>/dev/null)
    if [ -n "$swap" ] && [ "$swap" -gt 0 ]; then
      printf "%8d KB  %-20s  %s\n" "$swap" "$name" "$pid"
    fi
  done | sort -nr | head
}

export -f exterminatus
export -f who_use_port
export -f make_me_sudo
export -f unmake_me_sudo
export -f reswap
export -f who_use_swap
