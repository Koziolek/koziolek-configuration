#!/usr/bin/env bash

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


function resize_png() {
    # Argumenty: $1 - nazwa pliku, $2 - skala w procentach
    local scale=${2:-50}  # Skala domyślna to 50% (jeśli brak podano)

    # Sprawdź, czy podano poprawną wartość skali (liczby całkowite)
    if ! [[ "$scale" =~ ^[0-9]+$ ]] || [ "$scale" -le 0 ] || [ "$scale" -gt 100 ]; then
        log_error image.scale_invalid
        return 1
    fi

    # Jeśli podano nazwę pliku
    if [ -n "$1" ]; then
        # Sprawdź, czy plik istnieje i jest plikiem PNG
        if [ -f "$1" ] && [[ "$1" == *.png ]]; then
            log_info image.processing_file_scale "$1" "$scale"
            convert "$1" -resize "${scale}%" "$1"
        else
            log_error image.not_png "$1"
            return 1
        fi
    else
        # Jeśli nie podano nazwy pliku, przetwarzaj wszystkie pliki PNG w katalogu
        log_info image.processing_all_png "$scale"
        for file in *.png; do
            if [ -f "$file" ]; then
                log_info image.processing_file "$file"
                convert "$file" -resize "${scale}%" "$file"
            fi
        done
    fi

    log_info image.done
}

function resize_jpg() {
    # Argumenty: $1 - nazwa pliku, $2 - skala w procentach
    local scale=${2:-50}  # Skala domyślna to 50% (jeśli brak podano)

    # Sprawdź, czy podano poprawną wartość skali (liczby całkowite)
    if ! [[ "$scale" =~ ^[0-9]+$ ]] || [ "$scale" -le 0 ] || [ "$scale" -gt 100 ]; then
        log_error image.scale_invalid
        return 1
    fi

    # Jeśli podano nazwę pliku
    if [ -n "$1" ]; then
        # Sprawdź, czy plik istnieje i jest plikiem JPG/JPEG
        if [ -f "$1" ] && [[ "$1" =~ \.(jpg|jpeg|JPG|JPEG)$ ]]; then
            log_info image.processing_file_scale "$1" "$scale"
            convert "$1" -resize "${scale}%" "$1"
        else
            log_error image.not_jpg "$1"
            return 1
        fi
    else
        # Jeśli nie podano nazwy pliku, przetwarzaj wszystkie pliki JPG/JPEG w katalogu
        log_info image.processing_all_jpg "$scale"

        # Przetwarzaj pliki z różnymi rozszerzeniami
        for pattern in "*.jpg" "*.jpeg" "*.JPG" "*.JPEG"; do
            for file in $pattern; do
                if [ -f "$file" ]; then
                    log_info image.processing_file "$file"
                    convert "$file" -resize "${scale}%" "$file"
                fi
            done
        done
    fi

    log_info image.done
}

export -f heif_to_png
export -f resize_png
export -f resize_jpg
