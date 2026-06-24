#!/usr/bin/env bash


function turn_async_profiler_on() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    log_warn "turn_async_profiler_on: /proc/sys/kernel nie istnieje na macOS"
    return 1
  fi
  make_me_sudo
  $SUDO sh -c 'echo 1 > /proc/sys/kernel/perf_event_paranoid'
  $SUDO sh -c 'echo 0 > /proc/sys/kernel/kptr_restrict'
  unmake_me_sudo
}

function turn_async_profiler_off() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    log_warn "turn_async_profiler_off: /proc/sys/kernel nie istnieje na macOS"
    return 1
  fi
  make_me_sudo
  $SUDO sh -c 'echo 4 > /proc/sys/kernel/perf_event_paranoid'
  $SUDO sh -c 'echo 1 > /proc/sys/kernel/kptr_restrict'
  unmake_me_sudo
}

function java_clear() {
  local target_dir="${1:-.}"

  if ! command -v fdfind &>/dev/null; then
    log_error "java_clear: fdfind nie znaleziony"
    return 1
  fi

  while IFS= read -r build_file; do
    local dir
    dir="$(dirname "$build_file")"
    local filename
    filename="$(basename "$build_file")"

    if [[ "$filename" == "pom.xml" ]]; then
      log_info "java_clear: mvn clean w $dir"
      (cd "$dir" && mvn clean)
    elif [[ "$filename" == "build.gradle" || "$filename" == "build.gradle.kts" ]]; then
      log_info "java_clear: gradle clean w $dir"
      if [[ -f "$dir/gradlew" ]]; then
        (cd "$dir" && ./gradlew clean)
      else
        (cd "$dir" && gradle clean)
      fi
    fi
  done < <(fdfind -t f '(pom\.xml|build\.gradle(\.kts)?)' "$target_dir")
}

export -f turn_async_profiler_on
export -f turn_async_profiler_off
export -f java_clear
