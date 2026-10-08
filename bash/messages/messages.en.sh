#!/usr/bin/env bash
# Messages — English. Overlays messages.pl.sh; a key missing here falls back to Polish.
# Same layout: one array per log level, values are printf templates.

# --- MSG_DEBUG ---

# --- MSG_INFO ---
MSG_INFO[git.no_changes]="No changes"
MSG_INFO[java.clear_mvn]="java_clear: mvn clean in %s"
MSG_INFO[java.clear_gradle]="java_clear: gradle clean in %s"
MSG_INFO[misc.dir_created]="Created directory: %s"
MSG_INFO[diagnostic.hwinfo_install_hint]="hwinfo: install: sudo apt install dmidecode pciutils   (or: sudo yum install dmidecode pciutils)"
MSG_INFO[ssl.generated]="
  SSL certificates generated successfully!
    Certificate: %s
    Private key: %s
  "
MSG_INFO[ssl.next_steps]="
  Next steps:
  1. Add '127.0.0.1 koziolek.home' to your /etc/hosts file
  2. Run: docker compose up -d
  3. Access services at:
     - https://koziolek.home/nexus
     - https://koziolek.home/pgadmin"
MSG_INFO[certs.imported]="Certificate imported into %s"
MSG_INFO[process.killed_header]="Matched processes:"
MSG_INFO[process.no_listeners]="No listening processes"
MSG_INFO[process.no_listener_on_port]="No process listening on a port matching '%s'"

# --- MSG_WARN ---
MSG_WARN[install_lib.unknown_option]="Unknown option: -%s"
MSG_WARN[install_lib.no_access]="install_lib: no access to '%s' (private repo / unreachable from this machine) — skipping."
MSG_WARN[misc.dir_exists]="Directory '%s' already exists, skipping..."
MSG_WARN[diagnostic.hwinfo_needs_root]="hwinfo: dmidecode requires root — run via sudo"
MSG_WARN[hub.install_failed]="hub: installation via %s failed — git works without the alias"
MSG_WARN[darwin.reswap_unavailable]="reswap: swapoff/swapon unavailable on macOS"
MSG_WARN[darwin.who_use_swap_unavailable]="who_use_swap: /proc unavailable on macOS"
MSG_WARN[darwin.async_profiler_on_unavailable]="turn_async_profiler_on: /proc/sys/kernel does not exist on macOS"
MSG_WARN[darwin.async_profiler_off_unavailable]="turn_async_profiler_off: /proc/sys/kernel does not exist on macOS"
MSG_WARN[darwin.start_x_unavailable]="start_x: systemctl/lightdm unavailable on macOS"
MSG_WARN[darwin.fake_poweroff_unavailable]="fake_poweroff: gdbus/xset/wlopm unavailable on macOS — use pmset/caffeinate"
MSG_WARN[darwin.netconf_diag_unavailable]="netconf_diag: requires Linux tools (ip, iw, nmcli, journalctl) — unavailable on macOS"
MSG_WARN[darwin.refresh_apt_gpg_keys_unavailable]="refresh_apt_gpg_keys: apt unavailable on macOS"
MSG_WARN[darwin.pinentry_missing]="gpg: pinentry-mac missing (brew install pinentry-mac)"
MSG_WARN[nexus.secret_template_missing]="%s file not found"
MSG_WARN[certs.cert_missing]="Certificate %s does not exist - run prepare_cert first"
MSG_WARN[certs.no_sdkman_jdks]="Directory %s is missing - sdkman has no JDKs installed"
MSG_WARN[certs.no_cacerts]="No cacerts in %s, skipping"

# --- MSG_ERROR ---
MSG_ERROR[install_lib.repo_required]="Repository URL (-r) is required."
MSG_ERROR[install_lib.clone_failed]="Failed to clone repository '%s'."
MSG_ERROR[java.clear_no_fdfind]="java_clear: fdfind not found"
MSG_ERROR[weather.fetch_failed]="Unable to fetch weather for %s."
MSG_ERROR[diagnostic.hwinfo_missing_deps]="hwinfo: missing dependencies: %s"
MSG_ERROR[diagnostic.run_missing_script]="run_diagnostic: %s not found (fix-comp not cloned? check install_lib -p above)"
MSG_ERROR[certs.import_failed]="Failed to import certificate into %s"
MSG_ERROR[docker.compose_unavailable]="compose unavailable (DOCKER_COMPOSE='%s')"
MSG_ERROR[docker.container_name_required]="Container name parameter is required"
MSG_ERROR[docker.compose_file_missing]="❌ File %s does not exist!"
MSG_ERROR[docker.services_problems]="❌ Problems with services:"
MSG_ERROR[docker.services_start_failed]="❌ Failed to start services"

# --- MSG_MAN ---
MSG_MAN[install_lib.usage]="Usage: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>] [-x] [-p] [-h]"
MSG_MAN[prompt.answer_yn]="Please answer with 'y' or 'n'"
MSG_MAN[weather.usage]="Usage: get_weather <city_name>"
MSG_MAN[process.exterminatus_usage]="Usage
pray to Emperor and then:
  exterminatus PATTERN"
MSG_MAN[process.who_use_port_usage]="Usage: who_use_port [--sudo] PORT"
