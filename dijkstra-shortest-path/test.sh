#!/usr/bin/env bash
#
# Test runner for Dijkstra's Shortest Path solutions.
# Runs each solution against multiple test cases and reports pass/fail.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
SKIP=0

# --- Test cases ---
# Each test case is defined as a function that sets INPUT and EXPECTED.

declare -a TEST_NAMES
declare -a TEST_INPUTS
declare -a TEST_EXPECTED

# Test 1: Basic shortest path (example from problem statement)
TEST_NAMES+=("Basic shortest path (5 nodes, 6 edges)")
TEST_INPUTS+=("5 6
1 2 2
1 3 5
2 3 1
2 4 7
3 4 3
4 5 1")
TEST_EXPECTED+=("7")

# Test 2: Unreachable node
TEST_NAMES+=("Unreachable destination")
TEST_INPUTS+=("3 1
1 2 5")
TEST_EXPECTED+=("-1")

# Test 3: Single node (N=1), distance should be 0
TEST_NAMES+=("Single node (N=1)")
TEST_INPUTS+=("1 0")
TEST_EXPECTED+=("0")

# Test 4: Direct edge from 1 to N
TEST_NAMES+=("Direct edge from 1 to N")
TEST_INPUTS+=("2 1
1 2 42")
TEST_EXPECTED+=("42")

# Test 5: Multiple paths, choose shortest
TEST_NAMES+=("Multiple paths, shortest wins")
TEST_INPUTS+=("3 3
1 3 100
1 2 10
2 3 20")
TEST_EXPECTED+=("30")

# Test 6: Large weights (test 64-bit integers)
TEST_NAMES+=("Large weights (64-bit check)")
TEST_INPUTS+=("3 2
1 2 1000000000
2 3 1000000000")
TEST_EXPECTED+=("2000000000")

# Test 7: Diamond graph with different path costs
TEST_NAMES+=("Diamond graph")
TEST_INPUTS+=("4 5
1 2 1
1 3 10
2 3 1
2 4 100
3 4 1")
TEST_EXPECTED+=("3")

# Test 8: Linear chain
TEST_NAMES+=("Linear chain (5 nodes)")
TEST_INPUTS+=("5 4
1 2 1
2 3 2
3 4 3
4 5 4")
TEST_EXPECTED+=("10")

# Test 9: No edges at all with N > 1
TEST_NAMES+=("No edges, N > 1")
TEST_INPUTS+=("5 0")
TEST_EXPECTED+=("-1")

# Test 10: Parallel edges between same nodes
TEST_NAMES+=("Parallel edges (pick lighter one)")
TEST_INPUTS+=("2 3
1 2 100
1 2 50
1 2 75")
TEST_EXPECTED+=("50")

# --- Solution runners ---
# Each runner echoes the result of running the solution on stdin.

declare -a SOLUTION_NAMES
declare -a SOLUTION_CMDS
declare -a SOLUTION_READY

# Python
SOLUTION_NAMES+=("Python")
SOLUTION_CMDS+=("python3 solution.py")
if command -v python3 &>/dev/null; then
    SOLUTION_READY+=(1)
else
    SOLUTION_READY+=(0)
fi

# Ruby
SOLUTION_NAMES+=("Ruby")
SOLUTION_CMDS+=("ruby solution.rb")
if command -v ruby &>/dev/null; then
    SOLUTION_READY+=(1)
else
    SOLUTION_READY+=(0)
fi

# Go
SOLUTION_NAMES+=("Go")
SOLUTION_CMDS+=("go run solution.go")
if command -v go &>/dev/null; then
    SOLUTION_READY+=(1)
else
    SOLUTION_READY+=(0)
fi

# Zig (pre-compile, then run binary)
SOLUTION_NAMES+=("Zig")
ZIG_READY=0
if command -v zig &>/dev/null; then
    if zig build-exe solution.zig -OReleaseFast 2>/dev/null; then
        ZIG_READY=1
    fi
fi
SOLUTION_CMDS+=("./solution")
SOLUTION_READY+=("$ZIG_READY")

# --- Run tests ---

echo -e "${BOLD}Dijkstra's Shortest Path — Test Suite${NC}"
echo "======================================="
echo ""

NUM_TESTS=${#TEST_NAMES[@]}
NUM_SOLUTIONS=${#SOLUTION_NAMES[@]}

for ((s = 0; s < NUM_SOLUTIONS; s++)); do
    SOL_NAME="${SOLUTION_NAMES[$s]}"
    SOL_CMD="${SOLUTION_CMDS[$s]}"
    SOL_OK="${SOLUTION_READY[$s]}"

    echo -e "${BOLD}[$SOL_NAME]${NC}"

    if [[ "$SOL_OK" -eq 0 ]]; then
        echo -e "  ${YELLOW}SKIPPED${NC} — runtime not found"
        SKIP=$((SKIP + NUM_TESTS))
        echo ""
        continue
    fi

    for ((t = 0; t < NUM_TESTS; t++)); do
        TEST_NAME="${TEST_NAMES[$t]}"
        INPUT="${TEST_INPUTS[$t]}"
        EXPECTED="${TEST_EXPECTED[$t]}"

        # Run solution and capture output
        ACTUAL=$(echo "$INPUT" | eval "$SOL_CMD" 2>&1) || true
        ACTUAL=$(echo "$ACTUAL" | tr -d '[:space:]')

        if [[ "$ACTUAL" == "$EXPECTED" ]]; then
            echo -e "  ${GREEN}PASS${NC}  Test $((t + 1)): $TEST_NAME"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC}  Test $((t + 1)): $TEST_NAME"
            echo -e "        Expected: $EXPECTED"
            echo -e "        Actual:   $ACTUAL"
            FAIL=$((FAIL + 1))
        fi
    done

    echo ""
done

# Clean up Zig build artifacts
rm -f "$DIR/solution" "$DIR/solution.o"

# --- Summary ---

TOTAL=$((PASS + FAIL + SKIP))
echo "======================================="
echo -e "${BOLD}Results:${NC} $PASS passed, $FAIL failed, $SKIP skipped (out of $TOTAL)"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
