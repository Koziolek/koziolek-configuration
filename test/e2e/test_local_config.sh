#!/usr/bin/env bash
# E2E testy z podpiętym lokalnym projektem (--e2e-local).
# Weryfikuje lokalną konfigurację bez klonowania z GitHub.

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$PROJECT_ROOT/test/results}"
E2E_IMAGE="${E2E_IMAGE:-koziolek-test-e2e}"
LOG="$RESULTS_DIR/e2e-local.log"

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
echo "  E2E-LOCAL: konfiguracja z /project"
echo "======================================="

# --- Budowanie obrazu (reuse e2e) ---
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

# --- Uruchomienie kontenera z lokalnym projektem ---
echo ""
echo "▶ Uruchamianie kontenera z lokalnym projektem (może potrwać kilka minut)..."
docker run --rm \
    --network="${DOCKER_NETWORK:-koziolek-test-net}" \
    -v "$PROJECT_ROOT:/project:ro" \
    -v "$PROJECT_ROOT/test/e2e/entrypoint-local-test.sh:/entrypoint-local-test.sh:ro" \
    "$E2E_IMAGE" \
    bash /entrypoint-local-test.sh >> "$LOG" 2>&1
CONTAINER_EXIT=$?

# --- Weryfikacja ---
echo ""
echo "▶ Weryfikacja wyników..."

# testContainerExitsZero
if [[ $CONTAINER_EXIT -eq 0 ]]; then
    _pass "kontener zakończył się kodem 0"
else
    _fail "kontener zakończył się kodem $CONTAINER_EXIT (sprawdź $LOG)"
fi

# testFunctionsLoaded
_assert_log_contains \
    "funkcje z initial_packages.sh załadowane" \
    "FUNCTIONS_LOADED"

# testInstallPackagesDone
_assert_log_contains \
    "install_initial_packages zakończony" \
    "INSTALL_PACKAGES_DONE"

# testLocalWorkspaceLinked
_assert_log_contains \
    "lokalny projekt podpięty jako workspace" \
    "WORKSPACE_LOCAL_DONE"

# testBashrcPreparedFromLocalTemplate
_assert_log_contains \
    "prepare_bashrc zakończony z lokalnym szablonem" \
    "BASHRC_DONE"

# testBashrcContainsLocalConfig
_assert_log_contains \
    ".bashrc zawiera referencję do koziolek-configuration" \
    "BASHRC_CONTAINS_CONFIG"

# testSyntaxCheckPassed
_assert_log_contains \
    "składnia plików bash poprawna (bash -n)" \
    "SYNTAX_CHECK_DONE"

_assert_log_not_contains \
    "brak błędów składni (SYNTAX_FAIL)" \
    "SYNTAX_FAIL:"

# testProjectStructureComplete
_assert_log_contains \
    "weryfikacja struktury projektu zakończona" \
    "STRUCTURE_CHECK_DONE"

_assert_log_not_contains \
    "brak brakujących plików/katalogów (MISSING)" \
    "MISSING:"

# testNoTrapErrors
_assert_log_not_contains \
    "brak błędów z trap ERR (❌)" \
    "❌"

# --- Podsumowanie ---
echo ""
echo "======================================="
printf "  E2E-LOCAL Passed: %d   Failed: %d\n" "$PASS" "$FAIL"
echo "======================================="
echo "  Log: $LOG"
echo ""

[[ $FAIL -eq 0 ]]
