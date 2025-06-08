#!/usr/bin/env bash

function to_ascii() {
  local input="$*"
  echo "$input" | iconv -f utf8 -t ascii//TRANSLIT 2>/dev/null
}

function to_kebab_case() {
  local input="$*"
  echo "$input" | tr '[:upper:]' '[:lower:]' | sed -e 's/ /-/g' -e 's/^-//' -e 's/-$//'
}

function to_dot_case() {
  local input="$*"
  echo "$input" | tr '[:upper:]' '[:lower:]' | sed -e 's/ /./g' -e 's/^.//' -e 's/.$//'
}

function remove_special() {
  local input="$*"
  echo "${input//[^a-zA-Z0-9 _-]/}"
}

export -f to_ascii
export -f to_kebab_case
export -f to_dot_case
export -f remove_special
