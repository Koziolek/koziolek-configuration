#!/bin/bash

# add branch name at the beginning of commit message
# Pomija merge/squash (git sam generuje sensowny opis) i nie dubluje prefiksu,
# gdy pierwsza linia już zaczyna się od nazwy gałęzi (np. commit --amend).

BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT_FILE=$1
COMMIT_SOURCE=$2

case "$COMMIT_SOURCE" in
  merge|squash) exit 0 ;;
esac

FIRST_LINE=$(head -n1 "$COMMIT_FILE")
if [[ "$FIRST_LINE" == "$BRANCH "* ]]; then
  exit 0
fi

TEMP=$(mktemp)
{ printf '%s ' "$BRANCH"; cat "$COMMIT_FILE"; } > "$TEMP" && mv "$TEMP" "$COMMIT_FILE"
