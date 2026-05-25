#!/bin/bash

# use this hook if you would like to avoid commits to branch developer

if [ "$(git rev-parse --abbrev-ref HEAD)" = "developer" ] ;
then
  echo "no commits to dev";
  exit 1;
fi
