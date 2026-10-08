#!/usr/bin/env bash
# Komunikaty — język polski (bazowy: klucz bez tłumaczenia w innym języku wraca do tego pliku).
# Sourcowane przez messages_load (bash/functions.d/005_function_messages.sh) — tylko przypisania.
# Jedna tablica na poziom logowania; wartość to szablon dla printf (%s, %d). Używa ich
# wyłącznie odpowiadająca funkcja: log_debug → MSG_DEBUG, log_info → MSG_INFO, log_warn → MSG_WARN,
# log_error → MSG_ERROR, log_man → MSG_MAN. Klucze: <obszar>.<nazwa>.

# --- MSG_DEBUG ---

# --- MSG_INFO ---
MSG_INFO[git.no_changes]="Brak zmian"
MSG_INFO[java.clear_mvn]="java_clear: mvn clean w %s"
MSG_INFO[java.clear_gradle]="java_clear: gradle clean w %s"
MSG_INFO[misc.dir_created]="Utworzono katalog: %s"

# --- MSG_WARN ---
MSG_WARN[install_lib.unknown_option]="Nieznana opcja: -%s"
MSG_WARN[install_lib.no_access]="install_lib: brak dostępu do '%s' (repo prywatne/niedostępne z tej maszyny) — pomijam."
MSG_WARN[misc.dir_exists]="Katalog '%s' już istnieje, pomijam..."

# --- MSG_ERROR ---
MSG_ERROR[install_lib.repo_required]="Adres repozytorium (-r) jest obowiązkowy."
MSG_ERROR[install_lib.clone_failed]="Nie udało się sklonować repozytorium '%s'."
MSG_ERROR[java.clear_no_fdfind]="java_clear: fdfind nie znaleziony"
MSG_ERROR[weather.fetch_failed]="Nie udało się pobrać pogody dla %s."

# --- MSG_MAN ---
MSG_MAN[install_lib.usage]="Użycie: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>] [-x] [-p] [-h]"
MSG_MAN[prompt.answer_yn]="Odpowiedz 'y' lub 'n'"
MSG_MAN[weather.usage]="Użycie: get_weather <city_name>"
