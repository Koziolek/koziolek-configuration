#!/bin/bash

MAIN_BRANCH=`git config main.branch`; 

if [ "git rev-parse --abbrev-ref HEAD" = "$MAIN_BRANCH" ] ;
then
        echo "no commits to $MAIN_BRANCH";
        exit 1;
fi
