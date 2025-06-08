#!/usr/bin/env bash


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

export -f turn_async_profiler_on
export -f turn_async_profiler_off
