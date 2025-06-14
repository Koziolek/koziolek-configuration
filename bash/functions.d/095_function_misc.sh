#!/usr/bin/env bash

function install_lib() {
  local OPTIND opt;
  local repo_url=""
  local target_dir=""
  local exec_file=""
  local exp=false

  function _install_lib_show_help {
      cat <<EOF
Użycie: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>] [-x] [-h]
  -r: Adres repozytorium
  -t: Opcjonalny katalog docelowy
  -e: Opcjonalny plik wykonywalny
  -x: Uruchamia sourcing pliku wskazanego w -e
  -h: Wyświetl pomoc
EOF
  }

  function _install_lib_source {
    if [[ $exp == true ]]; then
     . "$target_dir/$exec_file"
    fi
  }

  while getopts ":hr:t:e:x" opt; do
    case "$opt" in
      h) 
        _install_lib_show_help
        return 0
        ;;
      r) repo_url="$OPTARG" ;; # Adres repozytorium
      t) target_dir="$OPTARG" ;; # Opcjonalny katalog docelowy
      e) exec_file="$OPTARG" ;; # Opcjonalny plik wykonywalny
      x) exp=true ;;
      *)
        log_warn "Nieznana opcja: -$OPTARG"
        log_man "Użycie: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>] [-x] [-h]"
        return 1
        ;;
    esac
  done

  if [ -z "$repo_url" ]; then
    log_error "Adres repozytorium (-r) jest obowiązkowy."
    log_man "Użycie: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>] [-x] [-h]"
    return 1
  fi

  if [ -n "$target_dir" ]; then
    target_dir="$WORKSPACE_TOOLS/$target_dir"
  else
    target_dir="$WORKSPACE_TOOLS/$(basename "$repo_url" .git)"
  fi

  if [ -d "$target_dir" ]; then
    _install_lib_source
    return 0
  fi

  if ! git clone "$repo_url" "$target_dir"; then
    log_error "Nie udało się sklonować repozytorium '$repo_url'."
    return 1
  fi

  if [ -n "$exec_file" ]; then
    if [ ! -x "$target_dir/$exec_file" ]; then
      chmod +x "$exec_file"
    fi
  fi

  _install_lib_source

  local OPTIND=1 # reset param pointer
}

function weather() {
      if [[ -z "$1" ]]; then
          log_man "Usage: get_weather <city_name>"
          return 1
      fi

      local city_name="$1"
      local response
      response=$(curl -s "wttr.in/${city_name}?format=%C+%t+%h+%w")

      if [[ -z "$response" ]]; then
          log_error "Unable to fetch weather for ${city_name}."
          return 1
      fi

      local weather_desc
      weather_desc=$(echo "$response" | awk '{print $1}')
      local temperature
      temperature=$(echo "$response" | awk '{print $2}')
      local humidity
      humidity=$(echo "$response" | awk '{print $3}')
      local wind_speed
      wind_speed=$(echo "$response" | awk '{print $4, $5}')

      echo "----------------------------------------"
      echo "| Weather in ${city_name}                   |"
      echo "----------------------------------------"
      printf "| %-15s | %-10s |\n" "Temperature" "${temperature}"
      printf "| %-15s | %-10s |\n" "Humidity" "${humidity}"
      printf "| %-15s | %-10s |\n" "Description" "${weather_desc}"
      printf "| %-15s | %-10s |\n" "Wind Speed" "${wind_speed}"
      echo "----------------------------------------"
}

export -f weather