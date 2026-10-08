#!/usr/bin/env bash

# Komunikaty z plików bash/messages/messages.<LANG>.sh — jedna tablica asocjacyjna na poziom
# logowania: MSG_DEBUG, MSG_INFO, MSG_WARN, MSG_ERROR, MSG_MAN. Klucz → szablon dla `printf`
# (placeholdery %s/%d). Czytają je wyłącznie funkcje log_<poziom> z 010_function_log.sh,
# każda tylko ze swojej tablicy; log_message dostaje gotowy komunikat.
#
# Ładowanie jest leniwe (pierwsze użycie komunikatu), więc start powłoki nic nie kosztuje.
# Zawsze ładowany jest najpierw język domyślny (pl), potem wybrany nakłada się na niego —
# klucz bez tłumaczenia pozostaje po polsku.
#
# Zmienne:
#   MESSAGES_LANG  wymuszenie języka (np. w ~/.senv), ma pierwszeństwo przed locale
#   MESSAGES_DIR   katalog z plikami messages.<LANG>.sh (domyślnie bash/messages obok tego pliku)

MESSAGES_DEFAULT_LANG="pl"
_MESSAGES_DIR_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../messages" 2>/dev/null && pwd)"

# Wybrany język (dwuliterowy kod): MESSAGES_LANG > LC_ALL > LC_MESSAGES > LANG; C/POSIX/puste → domyślny.
# Usage: messages_lang
function messages_lang() {
  local raw="${MESSAGES_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}}"
  raw="${raw%%[._@:]*}"   # pl_PL.UTF-8 → pl, en_GB → en
  raw="${raw%%_*}"
  raw="${raw,,}"
  case "$raw" in
  "" | c | posix) raw="$MESSAGES_DEFAULT_LANG" ;;
  esac
  echo "$raw"
}

# (Prze)ładuje tablice komunikatów dla bieżącego języka.
# Usage: messages_load
function messages_load() {
  local dir="${MESSAGES_DIR:-$_MESSAGES_DIR_DEFAULT}"
  local lang
  lang=$(messages_lang)

  declare -gA MSG_DEBUG MSG_INFO MSG_WARN MSG_ERROR MSG_MAN
  MSG_DEBUG=() MSG_INFO=() MSG_WARN=() MSG_ERROR=() MSG_MAN=()

  # shellcheck source=/dev/null
  [ -f "$dir/messages.${MESSAGES_DEFAULT_LANG}.sh" ] && . "$dir/messages.${MESSAGES_DEFAULT_LANG}.sh"
  if [ "$lang" != "$MESSAGES_DEFAULT_LANG" ] && [ -f "$dir/messages.${lang}.sh" ]; then
    # shellcheck source=/dev/null
    . "$dir/messages.${lang}.sh"
  fi
  MESSAGES_LOADED_LANG="$lang"
  MESSAGES_LOADED=1
}

function messages_ensure_loaded() {
  [ "${MESSAGES_LOADED:-}" = 1 ] || messages_load
}

export -f messages_lang
export -f messages_load
export -f messages_ensure_loaded
