#!/usr/bin/env bash
# Główny runner testów. Uruchamiany z katalogu głównego projektu.
#
# Użycie:
#   ./test/run.sh [opcje]
#
# Opcje:
#   --all               Uruchom wszystkie testy (unit + e2e + e2e-local + e2e-redhat + e2e-vanilla + e2e-certs)
#   --e2e               Uruchom testy e2e (initial_packages_ubuntu.sh + GitHub clone, wolne)
#   --e2e-local         Uruchom testy e2e z lokalnym projektem podpiętym jako volume
#   --e2e-redhat        Uruchom testy e2e dla initial_packages_redhat.sh (rockylinux:9, wolne)
#   --e2e-vanilla       Uruchom testy e2e dla initial_packages_vanilla.sh (debian:sid, wolne)
#   --e2e-certs         Uruchom testy TLS/cacerts (prawdziwy JDK+openssl, prepare_cert + update_sdkman_jdk_certs)
#   --native            Uruchom testy bezpośrednio na hoście (bez Docker) — wymagane na macOS
#   --filter <wzorzec>  Uruchom tylko pliki pasujące do wzorca (unit/integration)
#   --rebuild           Wymuś przebudowanie obrazów Docker
#   --help              Pokaż tę pomoc

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$PROJECT_ROOT/test"
RESULTS_DIR="$TEST_DIR/results"

# Wspólny znacznik czasu dla wszystkich kontenerów uruchomionych w tym
# wywołaniu run.sh — nazwy kontenerów: KOZIOLEK_CONFIGURATION_<rodzaj>_<TIMESTAMP>
# (patrz #34), zamiast losowych nazw nadawanych przez Dockera.
TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d%H%M%S)}"

UNIT_IMAGE="koziolek-test-unit"
E2E_IMAGE="koziolek-test-e2e"
E2E_REDHAT_IMAGE="koziolek-test-e2e-redhat"
E2E_VANILLA_IMAGE="koziolek-test-e2e-vanilla"
E2E_CERTS_IMAGE="koziolek-test-e2e-certs"

RUN_E2E=false
RUN_E2E_LOCAL=false
RUN_E2E_REDHAT=false
RUN_E2E_VANILLA=false
RUN_E2E_CERTS=false
RUN_NATIVE=false
TEST_FILTER=""
REBUILD=false
DOCKER_NETWORK="koziolek-test-net"

declare -A _E2E_JOB_PID=()
declare -A _E2E_JOB_LOG=()

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)        RUN_E2E=true; RUN_E2E_LOCAL=true; RUN_E2E_REDHAT=true; RUN_E2E_VANILLA=true; RUN_E2E_CERTS=true; shift ;;
        --e2e)        RUN_E2E=true; shift ;;
        --e2e-local)  RUN_E2E_LOCAL=true; shift ;;
        --e2e-redhat) RUN_E2E_REDHAT=true; shift ;;
        --e2e-vanilla) RUN_E2E_VANILLA=true; shift ;;
        --e2e-certs)  RUN_E2E_CERTS=true; shift ;;
        --native)     RUN_NATIVE=true; shift ;;
        --filter)     TEST_FILTER="$2"; shift 2 ;;
        --rebuild)    REBUILD=true; shift ;;
        --help|-h)    usage ;;
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

_preflight_docker() {
    echo "======================================="
    echo "  Sprawdzanie środowiska (Docker)"
    echo "======================================="

    _check_docker
    _check_network

    local base_ok=true
    _check_base_image "alpine:latest"   || base_ok=false
    if $RUN_E2E || $RUN_E2E_LOCAL; then
        _check_base_image "ubuntu:24.04" || base_ok=false
    fi
    if $RUN_E2E_REDHAT; then
        _check_base_image "rockylinux:9" || base_ok=false
    fi
    if $RUN_E2E_VANILLA; then
        _check_base_image "debian:sid" || base_ok=false
    fi
    if $RUN_E2E_CERTS; then
        _check_base_image "eclipse-temurin:21-jdk" || base_ok=false
    fi
    $base_ok || { echo ""; echo "  Brakujące obrazy bazowe — przerwanie."; exit 1; }

    _check_test_image "$UNIT_IMAGE" "$TEST_DIR/Dockerfile-unit"
    if $RUN_E2E || $RUN_E2E_LOCAL; then
        _check_test_image "$E2E_IMAGE" "$TEST_DIR/Dockerfile-e2e"
    fi
    if $RUN_E2E_REDHAT; then
        _check_test_image "$E2E_REDHAT_IMAGE" "$TEST_DIR/Dockerfile-e2e-redhat"
    fi
    if $RUN_E2E_VANILLA; then
        _check_test_image "$E2E_VANILLA_IMAGE" "$TEST_DIR/Dockerfile-e2e-vanilla"
    fi
    if $RUN_E2E_CERTS; then
        _check_test_image "$E2E_CERTS_IMAGE" "$TEST_DIR/Dockerfile-e2e-certs"
    fi

    echo "======================================="
    echo ""
}

_e2e_start() {
    # _e2e_start <klucz> <polecenie...> — odpala <polecenie> w tle (build+run+
    # weryfikacja kontenera dla jednego wariantu e2e), przechwytując CAŁY jego
    # output (stdout+stderr) do pliku tymczasowego, zamiast wypisywać na żywo —
    # kilka równoległych `docker build`/`docker run` przeplatałoby output na
    # terminalu w nieczytelny sposób. Wynik odtwarzany po kolei w _e2e_finish,
    # dopiero gdy wszystkie zadania się zakończą (patrz #128).
    local key="$1"; shift
    local log="$RESULTS_DIR/.e2e-parallel-${key}.log"
    : > "$log"
    ( "$@" ) >"$log" 2>&1 &
    _E2E_JOB_PID[$key]=$!
    _E2E_JOB_LOG[$key]=$log
}

_e2e_finish() {
    # _e2e_finish <klucz> — czeka na zadanie odpalone przez _e2e_start, wypisuje
    # jego przechwycony output i zwraca jego kod wyjścia.
    local key="$1" rc=0
    wait "${_E2E_JOB_PID[$key]}" || rc=$?
    echo ""
    echo "───────────────────────────────────────"
    echo "  Wynik: $key"
    echo "───────────────────────────────────────"
    cat "${_E2E_JOB_LOG[$key]}"
    rm -f "${_E2E_JOB_LOG[$key]}"
    return "$rc"
}

_preflight_native() {
    echo "======================================="
    echo "  Sprawdzanie środowiska (native: $(uname -s))"
    echo "======================================="

    if ! command -v bash >/dev/null 2>&1; then
        _fail "bash niedostępny"
        exit 1
    fi
    _ok "bash $(bash --version | head -1)"

    if [[ ! -f "${SHUNIT2:-}" ]] && ! command -v shunit2 >/dev/null 2>&1; then
        local shunit2_path
        shunit2_path="$(find "$PROJECT_ROOT" -name 'shunit2' -not -path '*/\.git/*' 2>/dev/null | head -1)"
        if [[ -n "$shunit2_path" ]]; then
            export SHUNIT2="$shunit2_path"
            _ok "shunit2: $SHUNIT2"
        else
            _fail "shunit2 nie znaleziony — sklonuj: git clone https://github.com/kward/shunit2.git \$WORKSPACE_TOOLS/shunit2"
            exit 1
        fi
    else
        _ok "shunit2: ${SHUNIT2:-system}"
    fi

    echo "======================================="
    echo ""
}

# ---------------------------------------------------------------------------

echo "======================================="
echo "  git-configuration test runner"
echo "======================================="
echo ""

# Każdy etap poniżej przechwytuje kod wyjścia przez `cmd || X_EXIT=$?` (nie
# `cmd; X_EXIT=$?`) - pod `set -e` niezerowy status prostego polecenia przerywa
# CAŁY skrypt w miejscu jego wystąpienia, zanim linia z `X_EXIT=$?` w ogóle się
# wykona, więc kolejne etapy (i finalne podsumowanie) nigdy by nie odpaliły
# (patrz #28).

# --- Testy jednostkowe i integracyjne ---
UNIT_EXIT=0
if $RUN_NATIVE; then
    _preflight_native

    echo "▶ Uruchamianie testów natywnie ($(uname -s))..."
    mkdir -p "$RESULTS_DIR"
    RESULTS_DIR="$RESULTS_DIR" TEST_FILTER="$TEST_FILTER" bash "$TEST_DIR/run-inside.sh" || UNIT_EXIT=$?
else
    _preflight_docker

    echo "▶ Uruchamianie testów unit/integration (Docker/Linux)..."
    docker run --rm \
        --name "KOZIOLEK_CONFIGURATION_unit_${TIMESTAMP}" \
        --network="$DOCKER_NETWORK" \
        -v "$PROJECT_ROOT:/project:ro" \
        -v "$RESULTS_DIR:/results" \
        -e "TEST_FILTER=$TEST_FILTER" \
        "$UNIT_IMAGE" || UNIT_EXIT=$?
fi

# --- Testy e2e: odpalane RÓWNOLEGLE w tle (patrz #128) ---------------------
# Każdy wariant (build+run+weryfikacja kontenera) to niezależny proces w innej
# sieci/na innym obrazie — poprzednio leciały jeden po drugim (seria IF-ów),
# mimo że nic ich nie synchronizuje. Teraz każdy odpalany jest w tle
# (_e2e_start), a doczekanie się i wypisanie wyniku (_e2e_finish) następuje
# dopiero po odpaleniu WSZYSTKICH żądanych wariantów — na kształt
# testcontainers, bez dodatkowej zależności (docker compose rozważany jako
# alternatywa, ale wymagałby przepisania asercji per-wariant na wspólny format
# `docker compose logs`; zwykłe zadania w tle są prostsze i nie ruszają
# istniejącej, przetestowanej logiki w test/e2e/*.sh).

if $RUN_E2E; then
    echo "▶ [w tle] e2e (Ubuntu)..."
    _e2e_start e2e env RESULTS_DIR="$RESULTS_DIR" E2E_IMAGE="$E2E_IMAGE" DOCKER_NETWORK="$DOCKER_NETWORK" TIMESTAMP="$TIMESTAMP" \
        bash "$TEST_DIR/e2e/test_initial_packages_ubuntu.sh"
fi
if $RUN_E2E_LOCAL; then
    echo "▶ [w tle] e2e-local..."
    _e2e_start e2e-local env RESULTS_DIR="$RESULTS_DIR" E2E_IMAGE="$E2E_IMAGE" DOCKER_NETWORK="$DOCKER_NETWORK" TIMESTAMP="$TIMESTAMP" \
        bash "$TEST_DIR/e2e/test_local_config.sh"
fi
if $RUN_E2E_REDHAT; then
    echo "▶ [w tle] e2e-redhat..."
    _e2e_start e2e-redhat env RESULTS_DIR="$RESULTS_DIR" E2E_REDHAT_IMAGE="$E2E_REDHAT_IMAGE" DOCKER_NETWORK="$DOCKER_NETWORK" TIMESTAMP="$TIMESTAMP" \
        bash "$TEST_DIR/e2e/test_initial_packages_redhat.sh"
fi
if $RUN_E2E_VANILLA; then
    echo "▶ [w tle] e2e-vanilla..."
    _e2e_start e2e-vanilla env RESULTS_DIR="$RESULTS_DIR" E2E_VANILLA_IMAGE="$E2E_VANILLA_IMAGE" DOCKER_NETWORK="$DOCKER_NETWORK" TIMESTAMP="$TIMESTAMP" \
        bash "$TEST_DIR/e2e/test_initial_packages_vanilla.sh"
fi
if $RUN_E2E_CERTS; then
    echo "▶ [w tle] e2e-certs..."
    _e2e_start e2e-certs docker run --rm \
        --name "KOZIOLEK_CONFIGURATION_e2e-certs_${TIMESTAMP}" \
        --network="$DOCKER_NETWORK" \
        -v "$PROJECT_ROOT:/project:ro" \
        "$E2E_CERTS_IMAGE"
fi

if $RUN_E2E || $RUN_E2E_LOCAL || $RUN_E2E_REDHAT || $RUN_E2E_VANILLA || $RUN_E2E_CERTS; then
    echo ""
    echo "▶ Czekam na zakończenie testów e2e uruchomionych w tle..."
fi

E2E_EXIT=0
$RUN_E2E && { _e2e_finish e2e || E2E_EXIT=$?; } || echo "▶ Testy e2e pominięte (--e2e aby uruchomić)"

E2E_LOCAL_EXIT=0
$RUN_E2E_LOCAL && { _e2e_finish e2e-local || E2E_LOCAL_EXIT=$?; } || echo "▶ Testy e2e-local pominięte (--e2e-local aby uruchomić)"

E2E_REDHAT_EXIT=0
$RUN_E2E_REDHAT && { _e2e_finish e2e-redhat || E2E_REDHAT_EXIT=$?; } || echo "▶ Testy e2e-redhat pominięte (--e2e-redhat aby uruchomić)"

E2E_VANILLA_EXIT=0
$RUN_E2E_VANILLA && { _e2e_finish e2e-vanilla || E2E_VANILLA_EXIT=$?; } || echo "▶ Testy e2e-vanilla pominięte (--e2e-vanilla aby uruchomić)"

E2E_CERTS_EXIT=0
$RUN_E2E_CERTS && { _e2e_finish e2e-certs || E2E_CERTS_EXIT=$?; } || echo "▶ Testy e2e-certs pominięte (--e2e-certs aby uruchomić)"

echo ""
echo "Wyniki: $RESULTS_DIR/"

[[ $UNIT_EXIT -eq 0 && $E2E_EXIT -eq 0 && $E2E_LOCAL_EXIT -eq 0 && $E2E_REDHAT_EXIT -eq 0 && $E2E_VANILLA_EXIT -eq 0 && $E2E_CERTS_EXIT -eq 0 ]]
