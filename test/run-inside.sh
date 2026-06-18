#!/usr/bin/env bash
# Uruchamiany wewnątrz kontenera lub natywnie (--native).
# Zbiera wyniki do /results/ lub $RESULTS_DIR.

set -euo pipefail

RESULTS_DIR="${RESULTS_DIR:-/results}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_FILTER="${TEST_FILTER:-}"
CURRENT_OS="$(uname -s)"

mkdir -p "$RESULTS_DIR"

PASS=0
FAIL=0
ERRORS=()

run_suite() {
    local suite_dir="$1"
    local suite_name="$2"

    [[ -d "$suite_dir" ]] || return 0

    for test_file in "$suite_dir"/test_*.sh; do
        [[ -f "$test_file" ]] || continue
        [[ -n "$TEST_FILTER" && "$test_file" != *"$TEST_FILTER"* ]] && continue

        local name
        name="$(basename "$test_file")"
        echo "▶ $suite_name/$name"

        if bash "$test_file" >> "$RESULTS_DIR/results.log" 2>&1; then
            echo "  ✓ OK"
            (( PASS++ )) || true
        else
            echo "  ✗ FAIL"
            (( FAIL++ )) || true
            ERRORS+=("$suite_name/$name")
        fi
    done
    return 0
}

{
    echo "======================================="
    echo "  Test run: $(date '+%Y-%m-%d %H:%M:%S')"
    printf "  OS: %s\n" "$CURRENT_OS"
    echo "======================================="
} | tee "$RESULTS_DIR/results.log"

# Testy wspólne (cross-platform)
run_suite "$SCRIPT_DIR/unit"        "unit"
run_suite "$SCRIPT_DIR/integration" "integration"

# Testy dedykowane dla bieżącego OS
if [[ "$CURRENT_OS" == "Darwin" ]]; then
    echo ""
    echo "--- Testy macOS (darwin) ---"
    run_suite "$SCRIPT_DIR/unit/darwin"        "unit/darwin"
    run_suite "$SCRIPT_DIR/integration/darwin" "integration/darwin"
else
    echo ""
    echo "--- Testy Linux (linux) ---"
    run_suite "$SCRIPT_DIR/unit/linux"         "unit/linux"
    run_suite "$SCRIPT_DIR/integration/linux"  "integration/linux"
fi

{
    echo ""
    echo "======================================="
    printf "  Passed: %d   Failed: %d\n" "$PASS" "$FAIL"
    echo "======================================="
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo "  Nieudane:"
        for e in "${ERRORS[@]}"; do echo "    - $e"; done
    fi
} | tee -a "$RESULTS_DIR/results.log"

[[ $FAIL -eq 0 ]]
