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

# --- MSG_WARN ---
MSG_WARN[install_lib.unknown_option]="Unknown option: -%s"
MSG_WARN[install_lib.no_access]="install_lib: no access to '%s' (private repo / unreachable from this machine) — skipping."
MSG_WARN[misc.dir_exists]="Directory '%s' already exists, skipping..."
MSG_WARN[diagnostic.hwinfo_needs_root]="hwinfo: dmidecode requires root — run via sudo"
MSG_WARN[hub.install_failed]="hub: installation via %s failed — git works without the alias"

# --- MSG_ERROR ---
MSG_ERROR[install_lib.repo_required]="Repository URL (-r) is required."
MSG_ERROR[install_lib.clone_failed]="Failed to clone repository '%s'."
MSG_ERROR[java.clear_no_fdfind]="java_clear: fdfind not found"
MSG_ERROR[weather.fetch_failed]="Unable to fetch weather for %s."
MSG_ERROR[diagnostic.hwinfo_missing_deps]="hwinfo: missing dependencies: %s"
MSG_ERROR[diagnostic.run_missing_script]="run_diagnostic: %s not found (fix-comp not cloned? check install_lib -p above)"

# --- MSG_MAN ---
MSG_MAN[install_lib.usage]="Usage: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>] [-x] [-p] [-h]"
MSG_MAN[prompt.answer_yn]="Please answer with 'y' or 'n'"
MSG_MAN[weather.usage]="Usage: get_weather <city_name>"
