#!/usr/bin/env bash
# Samodzielna aktualizacja git-bug — do crona (bez sudo, bez pytań, bez apt upgrade całego systemu).
#
#   cron_add -n git-bug daily ~/.koziolek-configuration/packages/update_git_bug.sh
#
# Brak binarki = instalacja. Wynik na stdout (cron_add kieruje go do ~/.cache/cron/git-bug.log).
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/git_bug.sh
source "$SCRIPT_DIR/git_bug.sh"

update_git_bug
