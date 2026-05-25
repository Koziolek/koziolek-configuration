#!/usr/bin/env bash
# Uruchamiany wewnątrz kontenera unit/integration. Zbiera wyniki do /results/.

set -euo pipefail

RESULTS_DIR="${RESULTS_DIR:-/results}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_FILTER="${TEST_FILTER:-}"

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
}

{
    echo "======================================="
    echo "  Test run: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "======================================="
} | tee "$RESULTS_DIR/results.log"

run_suite "$SCRIPT_DIR/unit"        "unit"
run_suite "$SCRIPT_DIR/integration" "integration"

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
