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
MSG_INFO[diagnostic.hwinfo_install_hint]="hwinfo: zainstaluj: sudo apt install dmidecode pciutils   (albo: sudo yum install dmidecode pciutils)"
MSG_INFO[ssl.generated]="
  Certyfikaty SSL wygenerowane pomyślnie!
    Certyfikat: %s
    Klucz prywatny: %s
  "
MSG_INFO[ssl.next_steps]="
  Następne kroki:
  1. Dodaj '127.0.0.1 koziolek.home' do pliku /etc/hosts
  2. Uruchom: docker compose up -d
  3. Usługi dostępne pod adresami:
     - https://koziolek.home/nexus
     - https://koziolek.home/pgadmin"
MSG_INFO[certs.imported]="Certyfikat zaimportowany do %s"

# --- MSG_WARN ---
MSG_WARN[install_lib.unknown_option]="Nieznana opcja: -%s"
MSG_WARN[install_lib.no_access]="install_lib: brak dostępu do '%s' (repo prywatne/niedostępne z tej maszyny) — pomijam."
MSG_WARN[misc.dir_exists]="Katalog '%s' już istnieje, pomijam..."
MSG_WARN[diagnostic.hwinfo_needs_root]="hwinfo: dmidecode wymaga uprawnień root — uruchom przez sudo"
MSG_WARN[hub.install_failed]="hub: instalacja przez %s nieudana — git działa bez aliasu"
MSG_WARN[darwin.reswap_unavailable]="reswap: swapoff/swapon niedostępne na macOS"
MSG_WARN[darwin.who_use_swap_unavailable]="who_use_swap: /proc niedostępny na macOS"
MSG_WARN[darwin.async_profiler_on_unavailable]="turn_async_profiler_on: /proc/sys/kernel nie istnieje na macOS"
MSG_WARN[darwin.async_profiler_off_unavailable]="turn_async_profiler_off: /proc/sys/kernel nie istnieje na macOS"
MSG_WARN[darwin.start_x_unavailable]="start_x: systemctl/lightdm niedostępne na macOS"
MSG_WARN[darwin.fake_poweroff_unavailable]="fake_poweroff: gdbus/xset/wlopm niedostępne na macOS — użyj pmset/caffeinate"
MSG_WARN[darwin.netconf_diag_unavailable]="netconf_diag: wymaga narzędzi Linux (ip, iw, nmcli, journalctl) — niedostępnych na macOS"
MSG_WARN[darwin.refresh_apt_gpg_keys_unavailable]="refresh_apt_gpg_keys: apt niedostępne na macOS"
MSG_WARN[darwin.pinentry_missing]="gpg: brak pinentry-mac (brew install pinentry-mac)"
MSG_WARN[nexus.secret_template_missing]="Nie znaleziono pliku %s"
MSG_WARN[certs.cert_missing]="Certyfikat %s nie istnieje - uruchom najpierw prepare_cert"
MSG_WARN[certs.no_sdkman_jdks]="Brak katalogu %s - sdkman nie ma zainstalowanych JDK"
MSG_WARN[certs.no_cacerts]="Brak cacerts w %s, pomijam"

# --- MSG_ERROR ---
MSG_ERROR[install_lib.repo_required]="Adres repozytorium (-r) jest obowiązkowy."
MSG_ERROR[install_lib.clone_failed]="Nie udało się sklonować repozytorium '%s'."
MSG_ERROR[java.clear_no_fdfind]="java_clear: fdfind nie znaleziony"
MSG_ERROR[weather.fetch_failed]="Nie udało się pobrać pogody dla %s."
MSG_ERROR[diagnostic.hwinfo_missing_deps]="hwinfo: brakujące zależności: %s"
MSG_ERROR[diagnostic.run_missing_script]="run_diagnostic: brak %s (fix-comp niesklonowany? sprawdź install_lib -p wyżej)"
MSG_ERROR[certs.import_failed]="Nie udało się zaimportować certyfikatu do %s"

# --- MSG_MAN ---
MSG_MAN[install_lib.usage]="Użycie: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>] [-x] [-p] [-h]"
MSG_MAN[prompt.answer_yn]="Odpowiedz 'y' lub 'n'"
MSG_MAN[weather.usage]="Użycie: get_weather <city_name>"
