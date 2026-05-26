#!/usr/bin/env bash
# E2E testy dla initial_packages.sh.
# Uruchamiany przez test/run.sh --e2e z katalogu głównego projektu.
# NIE używa shunit2 — orkiestruje Docker i analizuje log wyjściowy.

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$PROJECT_ROOT/test/results}"
E2E_IMAGE="${E2E_IMAGE:-koziolek-test-e2e}"
LOG="$RESULTS_DIR/e2e-initial-packages.log"

mkdir -p "$RESULTS_DIR"
: > "$LOG"

PASS=0
FAIL=0

_pass() { printf "  ✓ %s\n" "$1"; (( PASS++ )) || true; }
_fail() { printf "  ✗ %s\n" "$1"; (( FAIL++ )) || true; }

_assert_log_contains() {
    local desc="$1" pattern="$2"
    if grep -q "$pattern" "$LOG"; then _pass "$desc"; else _fail "$desc (brak: '$pattern')"; fi
}

_assert_log_not_contains() {
    local desc="$1" pattern="$2"
    if ! grep -q "$pattern" "$LOG"; then _pass "$desc"; else _fail "$desc (znaleziono: '$pattern')"; fi
}

echo "======================================="
echo "  E2E: initial_packages.sh"
echo "======================================="

# --- Budowanie obrazu ---
echo ""
echo "▶ Budowanie obrazu $E2E_IMAGE..."
if ! DOCKER_BUILDKIT=0 docker build \
        --network="${DOCKER_NETWORK:-koziolek-test-net}" \
        -f "$PROJECT_ROOT/test/Dockerfile-e2e" \
        -t "$E2E_IMAGE" \
        "$PROJECT_ROOT" >> "$LOG" 2>&1; then
    echo "  ✗ docker build nieudany — przerwanie"
    echo "  Log: $LOG"
    exit 1
fi
echo "  Obraz zbudowany."

# --- Uruchomienie kontenera ---
echo ""
echo "▶ Uruchamianie kontenera (może potrwać kilka minut)..."
docker run --rm \
    --network="${DOCKER_NETWORK:-koziolek-test-net}" \
    -v "$PROJECT_ROOT/test/e2e/entrypoint-test.sh:/entrypoint-test.sh:ro" \
    "$E2E_IMAGE" \
    bash /entrypoint-test.sh >> "$LOG" 2>&1
CONTAINER_EXIT=$?

# --- Weryfikacja ---
echo ""
echo "▶ Weryfikacja wyników..."

# testInitialPackagesExitsZero
if [[ $CONTAINER_EXIT -eq 0 ]]; then
    _pass "kontener zakończył się kodem 0"
else
    _fail "kontener zakończył się kodem $CONTAINER_EXIT (sprawdź $LOG)"
fi

# testFunctionsLoaded
_assert_log_contains \
    "funkcje z initial_packages.sh zostały załadowane" \
    "FUNCTIONS_LOADED"

# testInstallInitialPackagesRan
_assert_log_contains \
    "install_initial_packages uruchomiony i zakończony" \
    "INSTALL_PACKAGES_DONE"

# testWorkspaceCreated
_assert_log_contains \
    "prepare_workspace zakończony pomyślnie" \
    "WORKSPACE_DONE"

# testBashrcPrepared
_assert_log_contains \
    "prepare_bashrc zakończony pomyślnie" \
    "BASHRC_DONE"

# testBashrcContainsConfig
_assert_log_contains \
    ".bashrc zawiera referencję do koziolek-configuration" \
    "BASHRC_CONTAINS_CONFIG"

# testNoErrorLines (trap ERR z initial_packages.sh drukuje ❌)
_assert_log_not_contains \
    "brak linii błędu z trap ERR (❌)" \
    "❌"

# --- Podsumowanie ---
echo ""
echo "======================================="
printf "  E2E Passed: %d   Failed: %d\n" "$PASS" "$FAIL"
echo "======================================="
echo "  Log: $LOG"
echo ""

[[ $FAIL -eq 0 ]]
