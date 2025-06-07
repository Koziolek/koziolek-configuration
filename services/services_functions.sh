#!/usr/bin/env bash

# Function checking docker compose availability
check_docker_compose_availability() {
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

# Function checks container state
function check_container_status() {
  local container_name="$1"
  if [ -z "$container_name" ]; then
      log_error "Container name parameter is required"
      return 1
  fi

  local status

  if status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null); then
      echo "${C_GREEN}The '$container_name': $status${C_NC}"
      return 0
  else
      echo "${C_PURPLE}The '$container_name': does not exist${C_NC}"
      return 1
  fi
}

# Function checking docker-compose services state
function check_compose_status() {
    local compose_file="${1:-docker-compose.yaml}"

    echo -e "${C_BLUE}📋 Services state in $compose_file:${C_NC}"
    echo "================================"

    # Check if compose file exists
    if [ ! -f "$compose_file" ]; then
        log_error "❌ File $compose_file does not exist!"
        return 1
    fi

    # Determine which command to use
    local compose_cmd=$(check_docker_compose_availability)
    if [ $? -ne 0 ]; then
        log_error "❌ No working version of docker compose found!"
        log_info "  💡 Check Docker Compose installation"
        return 1
    fi

    echo -e "${C_GREEN}🔍 Using: $compose_cmd${C_NC}"

    # Uruchomienie odpowiedniej komendy
    case "$compose_cmd" in
        "docker compose")
            docker compose  -f "$compose_file" ps
            ;;
        "docker-compose")
            docker-compose -f "$compose_file" ps
            ;;
    esac
}


# Function checking if all services are healthy
function check_all_services_healthy() {
    local compose_file="${1:-docker-compose.yaml}"
    local failed_services=()

    # Określenie której komendy użyć
    local compose_cmd=$(check_docker_compose_availability)
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Nie znaleziono działającej wersji docker compose!${C_NC}"
        return 1
    fi

    # Pobieranie listy usług
    local services
    case "$compose_cmd" in
        "docker compose")
            services=$(docker compose -f "$compose_file" config --services 2>/dev/null)
            ;;
        "docker-compose")
            services=$(docker-compose -f "$compose_file" config --services 2>/dev/null)
            ;;
    esac

    for service in $services; do
        local container_name
        case "$compose_cmd" in
            "docker compose")
                container_name=$(docker compose -f "$compose_file" ps -q "$service" 2>/dev/null)
                ;;
            "docker-compose")
                container_name=$(docker-compose -f "$compose_file" ps -q "$service" 2>/dev/null)
                ;;
        esac

        if [ -n "$container_name" ]; then
            local status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null)

            if [ "$status" != "running" ]; then
                failed_services+=("$service ($status)")
            fi
        else
            failed_services+=("$service (not running)")
        fi
    done

    if [ ${#failed_services[@]} -eq 0 ]; then
        echo -e "${C_GREEN}✅ All services are working correctly${C_NC}"
        return 0
    else
        log_error "❌ Problems with services:"
        for service in "${failed_services[@]}"; do
            log_error "${C_RED}   - $service"
        done
        return 1
    fi
}

# Function to start Docker Compose services in detached mode
function start_compose_services() {
    local compose_file="${1:-docker-compose.yaml}"

    echo -e "${C_BLUE}🚀 Starting services from $compose_file...${C_NC}"

    # Check if compose file exists
    if [ ! -f "$compose_file" ]; then
        log_error "❌ File $compose_file does not exist!"
        return 1
    fi

    # Determine which command to use
    local compose_cmd=$(check_docker_compose_availability)
    if [ $? -ne 0 ]; then
        log_error "❌ No working version of docker compose found!"
        log_info "  💡 Check Docker Compose installation"
        return 1
    fi

    # Run appropriate command
    case "$compose_cmd" in
        "docker compose")
            docker compose -f "$compose_file" up -d
            ;;
        "docker-compose")
            docker-compose -f "$compose_file" up -d
            ;;
    esac

    if [ $? -eq 0 ]; then
        log_info "${C_GREEN}✅ Services started successfully${C_NC}"
        return 0
    else
        log_error "❌ Failed to start services"
        return 1
    fi
}

export -f check_container_status;
export -f check_compose_status;
export -f check_all_services_healthy;
export -f start_compose_services;