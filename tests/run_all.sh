#!/usr/bin/env bash
# ==============================================================================
# tests/run_all.sh — Hermetic, fast test runner with timeouts and clean summary
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PER_TEST_TIMEOUT="${TEST_TIMEOUT:-60}"
VERBOSE="${VERBOSE:-0}"

# Color output helpers if terminal supports colors
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_GREEN='\033[32m'
    C_RED='\033[31m'
    C_YELLOW='\033[33m'
    C_CYAN='\033[36m'
    C_GRAY='\033[90m'
else
    C_RESET=''
    C_BOLD=''
    C_GREEN=''
    C_RED=''
    C_YELLOW=''
    C_CYAN=''
    C_GRAY=''
fi

# Track test run statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TIMEOUT_TESTS=0
FAILURES=()

# Setup isolated hermetic test environment
TMP_ENV="$(mktemp -d /tmp/gps-hermetic-suite-XXXXXX)"

cleanup() {
    local exit_code=$?
    # Terminate any stray child processes started inside this runner
    if [ -n "${PID_LIST:-}" ]; then
        for pid in $PID_LIST; do
            if kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        sleep 0.05
        for pid in $PID_LIST; do
            if kill -0 "$pid" 2>/dev/null; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
        done
    fi
    rm -rf "$TMP_ENV" 2>/dev/null || true
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# Create isolated directory tree
mkdir -p "$TMP_ENV/home/.config/fontconfig" \
         "$TMP_ENV/home/.local/state" \
         "$TMP_ENV/home/.local/share" \
         "$TMP_ENV/home/.cache" \
         "$TMP_ENV/run" \
         "$TMP_ENV/stubs" \
         "$TMP_ENV/logs"

# Populate stubs via helper
python3 -c "
import sys
sys.path.insert(0, '$REPO_DIR')
from pathlib import Path
from tests.helpers import populate_stubs_dir
populate_stubs_dir(Path('$TMP_ENV/stubs'), Path('$TMP_ENV/stubs.log'))
"

# Link repo fontconfig for hermetic font tests
if [ -f "$REPO_DIR/dots/fontconfig/fonts.conf" ]; then
    ln -sf "$REPO_DIR/dots/fontconfig/fonts.conf" "$TMP_ENV/home/.config/fontconfig/fonts.conf"
fi

# Export hermetic environment
export HOME="$TMP_ENV/home"
export XDG_RUNTIME_DIR="$TMP_ENV/run"
export XDG_CONFIG_HOME="$TMP_ENV/home/.config"
export XDG_STATE_HOME="$TMP_ENV/home/.local/state"
export XDG_DATA_HOME="$TMP_ENV/home/.local/share"
export XDG_CACHE_HOME="$TMP_ENV/home/.cache"
export WAYLAND_DISPLAY=""
export DISPLAY=""
export HYPRLAND_INSTANCE_SIGNATURE=""
export PATH="$TMP_ENV/stubs:$PATH"
export PYTHONPATH="$REPO_DIR:${PYTHONPATH:-}"
export GPS_STUB_LOG="$TMP_ENV/stubs.log"

START_TIME=$(date +%s)

printf "%b========================================================================%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
printf "%b GPS Hermetic Test Suite Runner%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
printf "%b Repo: %s | Timeout: %ss per test%b\n" "$C_GRAY" "$REPO_DIR" "$PER_TEST_TIMEOUT" "$C_RESET"
printf "%b========================================================================%b\n\n" "$C_BOLD$C_CYAN" "$C_RESET"

run_single_test() {
    local runner="$1"
    local test_path="$2"
    local rel_path="${test_path#"$REPO_DIR/"}"
    local log_out="$TMP_ENV/logs/$(echo "$rel_path" | tr '/' '_').log"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local t0 t1 duration

    t0=$(date +%s%N 2>/dev/null || date +%s)

    set +e
    timeout "${PER_TEST_TIMEOUT}s" "$runner" "$test_path" < /dev/null >"$log_out" 2>&1
    local ret=$?
    set -e

    t1=$(date +%s%N 2>/dev/null || date +%s)
    if [ ${#t0} -gt 10 ]; then
        duration=$(awk -v t0="$t0" -v t1="$t1" 'BEGIN { printf "%.2f", (t1 - t0) / 1000000000 }')
    else
        duration=$((t1 - t0))
    fi

    if [ "$ret" -eq 124 ]; then
        TIMEOUT_TESTS=$((TIMEOUT_TESTS + 1))
        FAILURES+=("$rel_path (TIMEOUT after ${PER_TEST_TIMEOUT}s)")
        printf "  %-55s %bTIMEOUT%b (%ss)\n" "$rel_path" "$C_RED$C_BOLD" "$C_RESET" "$duration"
        if [ "$VERBOSE" -eq 1 ] || [ "$VERBOSE" = "true" ]; then
            tail -n 20 "$log_out" | sed 's/^/    /'
        fi
    elif [ "$ret" -eq 0 ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        printf "  %-55s %bPASS%b    (%ss)\n" "$rel_path" "$C_GREEN" "$C_RESET" "$duration"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILURES+=("$rel_path (exit code $ret)")
        printf "  %-55s %bFAIL%b    (%ss) [exit %d]\n" "$rel_path" "$C_RED$C_BOLD" "$C_RESET" "$duration" "$ret"
        printf "%b    --- Failure Log (tail) ---%b\n" "$C_GRAY" "$C_RESET"
        tail -n 15 "$log_out" | sed 's/^/    /'
        printf "%b    --------------------------%b\n" "$C_GRAY" "$C_RESET"
    fi
}

# 1. Run Python test suite
printf "%b[1/2] Running Python Tests...%b\n" "$C_BOLD" "$C_RESET"
for test_file in "$REPO_DIR"/tests/test_*.py; do
    if [ -f "$test_file" ]; then
        run_single_test python3 "$test_file"
    fi
done

printf "\n%b[2/2] Running Node Tests...%b\n" "$C_BOLD" "$C_RESET"
# 2. Run Node test suite across tests/, island/tests/, pet/tests/
for pattern in "$REPO_DIR/tests/*.js" "$REPO_DIR/island/tests/*.js" "$REPO_DIR/pet/tests/*.js"; do
    for test_file in $pattern; do
        if [ -f "$test_file" ]; then
            run_single_test node "$test_file"
        fi
    done
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

printf "\n%b========================================================================%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
printf "%b Test Suite Summary%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
printf "%b========================================================================%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
printf "  Total Tests  : %d\n" "$TOTAL_TESTS"
printf "  Passed       : %b%d%b\n" "$C_GREEN" "$PASSED_TESTS" "$C_RESET"

if [ "$FAILED_TESTS" -gt 0 ]; then
    printf "  Failed       : %b%d%b\n" "$C_RED$C_BOLD" "$FAILED_TESTS" "$C_RESET"
else
    printf "  Failed       : 0\n"
fi

if [ "$TIMEOUT_TESTS" -gt 0 ]; then
    printf "  Timed out    : %b%d%b\n" "$C_YELLOW$C_BOLD" "$TIMEOUT_TESTS" "$C_RESET"
else
    printf "  Timed out    : 0\n"
fi

printf "  Duration     : %ds\n" "$TOTAL_DURATION"
printf "%b========================================================================%b\n" "$C_BOLD$C_CYAN" "$C_RESET"

if [ ${#FAILURES[@]} -gt 0 ]; then
    printf "\n%bFailed / Timed-out Test List:%b\n" "$C_RED$C_BOLD" "$C_RESET"
    for fail in "${FAILURES[@]}"; do
        printf "  - %b%s%b\n" "$C_RED" "$fail" "$C_RESET"
    done
    exit 1
fi

printf "\n%bALL %d TESTS PASSED SUCCESFULLY!%b\n\n" "$C_GREEN$C_BOLD" "$TOTAL_TESTS" "$C_RESET"
exit 0
