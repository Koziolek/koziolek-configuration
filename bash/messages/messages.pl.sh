#!/usr/bin/env bash
# Komunikaty — język polski (bazowy: klucz bez tłumaczenia w innym języku wraca do tego pliku).
# Sourcowane przez messages_load (bash/functions.d/005_function_messages.sh) — tylko przypisania.
# Jedna tablica na poziom logowania; wartość to szablon dla printf (%s, %d). Używa ich
# wyłącznie odpowiadająca funkcja: log_debug → MSG_DEBUG, log_info → MSG_INFO, log_warn → MSG_WARN,
# log_error → MSG_ERROR, log_man → MSG_MAN. Klucze: <obszar>.<nazwa>.

# --- MSG_DEBUG ---

# --- MSG_INFO ---
MSG_INFO[git.no_changes]="Brak zmian"

# --- MSG_WARN ---
MSG_WARN[install_lib.unknown_option]="Nieznana opcja: -%s"
MSG_WARN[install_lib.no_access]="install_lib: brak dostępu do '%s' (repo prywatne/niedostępne z tej maszyny) — pomijam."

# --- MSG_ERROR ---
MSG_ERROR[install_lib.repo_required]="Adres repozytorium (-r) jest obowiązkowy."
MSG_ERROR[install_lib.clone_failed]="Nie udało się sklonować repozytorium '%s'."

# --- MSG_MAN ---
MSG_MAN[install_lib.usage]="Użycie: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>] [-x] [-p] [-h]"
MSG_MAN[prompt.answer_yn]="Odpowiedz 'y' lub 'n'"
