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
  if [ ! -d "$WORKSPACE" ]; then
    mkdir -p "$WORKSPACE";
  fi
  if [ ! -d "$WORKSPACE_TOOLS" ]; then
    mkdir -p "$WORKSPACE_TOOLS";
  fi
}


source_directory "$BASH_CONFIGURATION_DIR/functions.d/"

##
# Export unexported „by default” functions so they remain available after 'source'
##
export -f bash_customs_usage
export -f supports_colors
