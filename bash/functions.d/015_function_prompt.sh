#!/usr/bin/env bash

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

export -f are_you_sure
export -f yes_or_no
