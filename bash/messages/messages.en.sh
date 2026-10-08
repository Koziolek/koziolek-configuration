#!/usr/bin/env bash
# Messages — English. Overlays messages.pl.sh; a key missing here falls back to Polish.
# Same layout: one array per log level, values are printf templates.

# --- MSG_DEBUG ---

# --- MSG_INFO ---
MSG_INFO[git.no_changes]="No changes"

# --- MSG_WARN ---
MSG_WARN[install_lib.unknown_option]="Unknown option: -%s"
MSG_WARN[install_lib.no_access]="install_lib: no access to '%s' (private repo / unreachable from this machine) — skipping."

# --- MSG_ERROR ---
MSG_ERROR[install_lib.repo_required]="Repository URL (-r) is required."
MSG_ERROR[install_lib.clone_failed]="Failed to clone repository '%s'."

# --- MSG_MAN ---
MSG_MAN[install_lib.usage]="Usage: clone_and_check_file -r <repo_url> [-t <target_dir>] [-e <exec_file>] [-x] [-p] [-h]"
MSG_MAN[prompt.answer_yn]="Please answer with 'y' or 'n'"
