#!/usr/bin/env bash
#
# Test script for Fibonacci with Matrix Exponentiation solutions.
# Runs each solution against a set of test cases and reports pass/fail.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
TOTAL=0

# Test cases: "input expected_output"
declare -a TESTS=(
    "0 0"
    "1 1"
    "2 1"
    "10 55"
    "100 687995182"
    "1000 517691607"
    "1000000000 21"
    "1000000000000000000 209783453"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_result() {
    local lang="$1"
    local input="$2"
    local expected="$3"
    local actual="$4"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        printf "  ${GREEN}PASS${NC}  %-8s N=%-22s expected=%-12s got=%s\n" "[$lang]" "$input" "$expected" "$actual"
    else
        FAIL=$((FAIL + 1))
        printf "  ${RED}FAIL${NC}  %-8s N=%-22s expected=%-12s got=%s\n" "[$lang]" "$input" "$expected" "$actual"
    fi
}

echo "========================================"
echo " Fibonacci Matrix Exponentiation Tests"
echo "========================================"
echo ""

# --- Python ---
if command -v python3 &>/dev/null; then
    echo "${YELLOW}Python:${NC}"
    for tc in "${TESTS[@]}"; do
        input="${tc%% *}"
        expected="${tc##* }"
        actual=$(echo "$input" | python3 "$DIR/solution.py" 2>/dev/null || echo "ERROR")
        actual=$(echo "$actual" | tr -d '[:space:]')
        print_result "Python" "$input" "$expected" "$actual"
    done
    echo ""
else
    echo "Skipping Python (python3 not found)"
fi

# --- Ruby ---
if command -v ruby &>/dev/null; then
    echo "${YELLOW}Ruby:${NC}"
    for tc in "${TESTS[@]}"; do
        input="${tc%% *}"
        expected="${tc##* }"
        actual=$(echo "$input" | ruby "$DIR/solution.rb" 2>/dev/null || echo "ERROR")
        actual=$(echo "$actual" | tr -d '[:space:]')
        print_result "Ruby" "$input" "$expected" "$actual"
    done
    echo ""
else
    echo "Skipping Ruby (ruby not found)"
fi

# --- Go ---
if command -v go &>/dev/null; then
    echo "${YELLOW}Go:${NC}"
    GO_BIN=$(mktemp)
    if go build -o "$GO_BIN" "$DIR/solution.go" 2>/dev/null; then
        for tc in "${TESTS[@]}"; do
            input="${tc%% *}"
            expected="${tc##* }"
            actual=$(echo "$input" | "$GO_BIN" 2>/dev/null || echo "ERROR")
            actual=$(echo "$actual" | tr -d '[:space:]')
            print_result "Go" "$input" "$expected" "$actual"
        done
    else
        echo "  Failed to compile Go solution"
    fi
    rm -f "$GO_BIN"
    echo ""
else
    echo "Skipping Go (go not found)"
fi

# --- Zig ---
if command -v zig &>/dev/null; then
    echo "${YELLOW}Zig:${NC}"
    ZIG_BIN="$DIR/solution_zig"
    rm -f "$ZIG_BIN"
    if zig build-exe "$DIR/solution.zig" -femit-bin="$ZIG_BIN" -O ReleaseFast --cache-dir /tmp/zig-cache 2>/dev/null; then
        for tc in "${TESTS[@]}"; do
            input="${tc%% *}"
            expected="${tc##* }"
            actual=$(echo "$input" | "$ZIG_BIN" 2>/dev/null || echo "ERROR")
            actual=$(echo "$actual" | tr -d '[:space:]')
            print_result "Zig" "$input" "$expected" "$actual"
        done
        rm -f "$ZIG_BIN"
        rm -rf "$DIR/solution_zig.o"
    else
        echo "  Failed to compile Zig solution"
    fi
    echo ""
else
    echo "Skipping Zig (zig not found)"
fi

# --- Summary ---
echo "========================================"
printf "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, %d total\n" "$PASS" "$FAIL" "$TOTAL"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
