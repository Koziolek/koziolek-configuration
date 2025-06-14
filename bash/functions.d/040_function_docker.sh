#!/usr/bin/env bash

# Function checking docker compose availability
function check_docker_compose_availability() {
    if docker compose version &>/dev/null; then
        echo "docker compose"
        return 0
    elif command -v docker-compose &>/dev/null && docker-compose version &>/dev/null; then
        echo "docker-compose"
        return 0
    else
        return 1
    fi
}

