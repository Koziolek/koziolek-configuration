#!/usr/bin/env bash

function log_message() {
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

export -f log_message
export -f log_debug
export -f log_info
export -f log_warn
export -f log_error
export -f log_man