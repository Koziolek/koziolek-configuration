#!/usr/bin/env bash

function to_ascii() {
  local input="$*"
  echo "$input" | iconv -f utf8 -t ascii//TRANSLIT 2>/dev/null
}

function to_kebab_case() {
  local input="$*"
  echo "$input" | tr '[:upper:]' '[:lower:]' | sed -e 's/ /-/g' -e 's/^-//' -e 's/-$//'
}

export -f to_ascii
export -f to_kebab_case