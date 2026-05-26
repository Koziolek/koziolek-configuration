#!/usr/bin/env bash
# Główny runner testów. Uruchamiany z katalogu głównego projektu.
#
# Użycie:
#   ./test/run.sh [opcje]
#
# Opcje:
#   --all               Uruchom wszystkie testy (unit + e2e + e2e-local)
#   --e2e               Uruchom testy e2e (initial_packages.sh + GitHub clone, wolne)
#   --e2e-local         Uruchom testy e2e z lokalnym projektem podpiętym jako volume
#   --filter <wzorzec>  Uruchom tylko pliki pasujące do wzorca (unit/integration)
#   --rebuild           Wymuś przebudowanie obrazów Docker
#   --help              Pokaż tę pomoc

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$PROJECT_ROOT/test"
RESULTS_DIR="$TEST_DIR/results"

UNIT_IMAGE="koziolek-test-unit"
E2E_IMAGE="koziolek-test-e2e"

RUN_E2E=false
RUN_E2E_LOCAL=false
TEST_FILTER=""
REBUILD=false
DOCKER_NETWORK="koziolek-test-net"

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)       RUN_E2E=true; RUN_E2E_LOCAL=true; shift ;;
        --e2e)       RUN_E2E=true; shift ;;
        --e2e-local) RUN_E2E_LOCAL=true; shift ;;
        --filter)    TEST_FILTER="$2"; shift 2 ;;
        --rebuild)   REBUILD=true; shift ;;
        --help|-h)   usage ;;
        *) echo "Nieznana opcja: $1"; exit 1 ;;
    esac
done

mkdir -p "$RESULTS_DIR"

# ---------------------------------------------------------------------------
# Helpery

_ok()   { printf "  ✓ %s\n" "$1"; }
_fix()  { printf "  ⚙ %s\n" "$1"; }
_fail() { printf "  ✗ %s\n" "$1"; }

_check_docker() {
    if docker info &>/dev/null; then
        _ok "Docker daemon działa"
    else
        _fail "Docker daemon niedostępny — uruchom dockera i spróbuj ponownie"
        exit 1
    fi
}

_check_network() {
    if docker network inspect "$DOCKER_NETWORK" &>/dev/null; then
        _ok "Sieć $DOCKER_NETWORK"
    else
        _fix "Tworzenie sieci $DOCKER_NETWORK..."
        docker network create --driver bridge "$DOCKER_NETWORK" >/dev/null
        _ok "Sieć $DOCKER_NETWORK utworzona"
    fi
}

_check_base_image() {
    local image="$1"
    if [[ -n "$(docker images -q "$image" 2>/dev/null)" ]]; then
        _ok "Obraz bazowy $image"
    else
        _fix "Pobieranie obrazu $image..."
        if DOCKER_BUILDKIT=0 docker pull --quiet "$image" >/dev/null 2>&1; then
            _ok "Obraz bazowy $image pobrany"
        else
            _fail "Nie można pobrać $image (brak dostępu do Docker Hub)"
            echo "    Pobierz ręcznie na maszynie z dostępem: docker pull $image"
            return 1
        fi
    fi
}

_check_test_image() {
    local tag="$1" dockerfile="$2"
    if $REBUILD; then
        _fix "Przebudowanie obrazu $tag (--rebuild)..."
    elif [[ -z "$(docker images -q "$tag" 2>/dev/null)" ]]; then
        _fix "Budowanie obrazu $tag..."
    else
        _ok "Obraz testowy $tag"
        return 0
    fi

    if DOCKER_BUILDKIT=0 docker build \
            --network="$DOCKER_NETWORK" \
            -f "$dockerfile" -t "$tag" \
            "$PROJECT_ROOT" >/dev/null 2>&1; then
        _ok "Obraz testowy $tag zbudowany"
    else
        _fail "Budowanie $tag nieudane"
        echo "    Sprawdź ręcznie: DOCKER_BUILDKIT=0 docker build --network=$DOCKER_NETWORK -f $dockerfile -t $tag $PROJECT_ROOT"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Preflight: sprawdza i konfiguruje środowisko przed uruchomieniem testów

_preflight() {
    echo "======================================="
    echo "  Sprawdzanie środowiska"
    echo "======================================="

    _check_docker
    _check_network

    local base_ok=true
    _check_base_image "alpine:latest"   || base_ok=false
    if $RUN_E2E || $RUN_E2E_LOCAL; then
        _check_base_image "ubuntu:24.04" || base_ok=false
    fi
    $base_ok || { echo ""; echo "  Brakujące obrazy bazowe — przerwanie."; exit 1; }

    _check_test_image "$UNIT_IMAGE" "$TEST_DIR/Dockerfile-unit"
    if $RUN_E2E || $RUN_E2E_LOCAL; then
        _check_test_image "$E2E_IMAGE" "$TEST_DIR/Dockerfile-e2e"
    fi

    echo "======================================="
    echo ""
}

# ---------------------------------------------------------------------------

echo "======================================="
echo "  git-configuration test runner"
echo "======================================="
echo ""

_preflight

# --- Testy jednostkowe i integracyjne ---
echo "▶ Uruchamianie testów unit/integration..."
docker run --rm \
    --network="$DOCKER_NETWORK" \
    -v "$PROJECT_ROOT:/project:ro" \
    -v "$RESULTS_DIR:/results" \
    -e "TEST_FILTER=$TEST_FILTER" \
    "$UNIT_IMAGE"
UNIT_EXIT=$?

# --- Testy e2e (GitHub clone) ---
if $RUN_E2E; then
    echo ""
    echo "▶ Uruchamianie testów e2e..."
    RESULTS_DIR="$RESULTS_DIR" E2E_IMAGE="$E2E_IMAGE" DOCKER_NETWORK="$DOCKER_NETWORK" \
        bash "$TEST_DIR/e2e/test_initial_packages.sh"
    E2E_EXIT=$?
else
    E2E_EXIT=0
    echo "▶ Testy e2e pominięte (--e2e aby uruchomić)"
fi

# --- Testy e2e-local (lokalny projekt) ---
if $RUN_E2E_LOCAL; then
    echo ""
    echo "▶ Uruchamianie testów e2e-local..."
    RESULTS_DIR="$RESULTS_DIR" E2E_IMAGE="$E2E_IMAGE" DOCKER_NETWORK="$DOCKER_NETWORK" \
        bash "$TEST_DIR/e2e/test_local_config.sh"
    E2E_LOCAL_EXIT=$?
else
    E2E_LOCAL_EXIT=0
    echo "▶ Testy e2e-local pominięte (--e2e-local aby uruchomić)"
fi

echo ""
echo "Wyniki: $RESULTS_DIR/"

[[ $UNIT_EXIT -eq 0 && $E2E_EXIT -eq 0 && $E2E_LOCAL_EXIT -eq 0 ]]
