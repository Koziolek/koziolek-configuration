#!/bin/bash

# add branch name at the begining of commit message

BRANCH=`git branch | grep '*' | awk '{print $2}'`;
COMMIT_FILE=$1

echo "$BRANCH "| cat $COMMIT_FILE > temp && mv temp $COMMIT_FILE
