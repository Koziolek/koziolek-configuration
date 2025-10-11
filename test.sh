#!/usr/bin/env bash

docker rmi test-koziolek-configuration

docker build -f Dockerfile-test -t test-koziolek-configuration .

docker run --rm test-koziolek-configuration
