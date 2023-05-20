#!/bin/bash

set -euo pipefail

INAME=git_configuration_test

docker rm $INAME || echo "NO IMAGE"

docker build -t $INAME .

docker run --name $INAME $INAME

docker rm $INAME
