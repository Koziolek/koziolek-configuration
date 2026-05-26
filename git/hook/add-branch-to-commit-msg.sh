#!/bin/bash

# add branch name at the begining of commit message

BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT_FILE=$1
TEMP=$(mktemp)

{ echo "$BRANCH "; cat "$COMMIT_FILE"; } > "$TEMP" && mv "$TEMP" "$COMMIT_FILE"
