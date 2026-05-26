#!/bin/bash

MAIN_BRANCH=$(git config main.branch 2>/dev/null || git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")

if [ "$(git rev-parse --abbrev-ref HEAD)" = "$MAIN_BRANCH" ] ;
then
        echo "no commits to $MAIN_BRANCH";
        exit 1;
fi
