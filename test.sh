#!/bin/bash

set -euo pipefail
INAME=git_configuration_test

docker build -t $INAME .

docker run --name $INAME $INAME

docker rm $INAME