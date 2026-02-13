#!/usr/bin/env bash
# test.sh - Test runner for segment tree range query solutions
#
# Compiles Go and Zig solutions, then runs all solutions against multiple
# test cases and reports pass/fail for each.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
SKIP=0

# ---- Test Cases ----
# Each test case is a pair: input and expected output.

# Test 1: Basic example with update and queries
INPUT_1="5 5
1 2 3 4 5
2 1 3
1 2 5
2 1 3
2 1 5
2 3 5"
EXPECTED_1="6
9
18
12"

# Test 2: Single element
INPUT_2="1 3
1000000000
2 1 1
1 1 999999999
2 1 1"
EXPECTED_2="1000000000
999999999"

# Test 3: All queries, no updates
INPUT_3="4 3
10 20 30 40
2 1 4
2 2 3
2 4 4"
EXPECTED_3="100
50
40"

# Test 4: All updates, then one query
INPUT_4="3 4
10 20 30
1 1 100
1 2 200
1 3 300
2 1 3"
EXPECTED_4="600"

# Test 5: Alternating updates and queries, single element ranges
INPUT_5="5 8
5 4 3 2 1
2 3 3
1 3 10
2 3 3
2 1 5
1 1 100
1 5 100
2 1 5
2 2 4"
EXPECTED_5="3
10
22
216
16"

# Test 6: Large values (testing 64-bit sums)
INPUT_6="3 2
1000000000 1000000000 1000000000
2 1 3
2 1 2"
EXPECTED_6="3000000000
2000000000"

# Test 7: Edge case - query single element, update same element, query again
INPUT_7="2 4
7 3
2 1 1
2 2 2
1 1 99
2 1 2"
EXPECTED_7="7
3
102"

INPUTS=("$INPUT_1" "$INPUT_2" "$INPUT_3" "$INPUT_4" "$INPUT_5" "$INPUT_6" "$INPUT_7")
EXPECTED=("$EXPECTED_1" "$EXPECTED_2" "$EXPECTED_3" "$EXPECTED_4" "$EXPECTED_5" "$EXPECTED_6" "$EXPECTED_7")

# ---- Compile Go and Zig ----

echo -e "${YELLOW}=== Compiling solutions ===${NC}"

GO_BIN=""
if command -v go &>/dev/null; then
    echo "Compiling Go..."
    if go build -o solution_go solution.go 2>&1; then
        GO_BIN="./solution_go"
        echo -e "${GREEN}Go compiled successfully${NC}"
    else
        echo -e "${RED}Go compilation failed${NC}"
    fi
else
    echo -e "${YELLOW}Go not found, skipping${NC}"
fi

ZIG_BIN=""
if command -v zig &>/dev/null; then
    echo "Compiling Zig..."
    if zig build-exe solution.zig -O ReleaseFast -femit-bin=solution_zig 2>&1; then
        ZIG_BIN="./solution_zig"
        echo -e "${GREEN}Zig compiled successfully${NC}"
    else
        echo -e "${RED}Zig compilation failed${NC}"
    fi
else
    echo -e "${YELLOW}Zig not found, skipping${NC}"
fi

echo ""

# ---- Define runners ----
# Each runner is: name, command
declare -a RUNNERS=()
declare -a RUNNER_NAMES=()

if command -v python3 &>/dev/null; then
    RUNNERS+=("python3 solution.py")
    RUNNER_NAMES+=("Python")
elif command -v python &>/dev/null; then
    RUNNERS+=("python solution.py")
    RUNNER_NAMES+=("Python")
else
    echo -e "${YELLOW}Python not found, skipping${NC}"
fi

if command -v ruby &>/dev/null; then
    RUNNERS+=("ruby solution.rb")
    RUNNER_NAMES+=("Ruby")
else
    echo -e "${YELLOW}Ruby not found, skipping${NC}"
fi

if [[ -n "$GO_BIN" ]]; then
    RUNNERS+=("$GO_BIN")
    RUNNER_NAMES+=("Go")
fi

if [[ -n "$ZIG_BIN" ]]; then
    RUNNERS+=("$ZIG_BIN")
    RUNNER_NAMES+=("Zig")
fi

if [[ ${#RUNNERS[@]} -eq 0 ]]; then
    echo -e "${RED}No solutions available to test!${NC}"
    exit 1
fi

# ---- Run tests ----

echo -e "${YELLOW}=== Running tests ===${NC}"
echo ""

for runner_idx in "${!RUNNERS[@]}"; do
    runner="${RUNNERS[$runner_idx]}"
    name="${RUNNER_NAMES[$runner_idx]}"
    echo -e "${YELLOW}--- ${name} ---${NC}"

    for tc_idx in "${!INPUTS[@]}"; do
        tc_num=$((tc_idx + 1))
        input="${INPUTS[$tc_idx]}"
        expected="${EXPECTED[$tc_idx]}"

        # Run the solution and capture output
        actual=$(echo "$input" | $runner 2>&1) || true

        # Normalize: trim trailing whitespace/newlines
        expected_norm=$(echo "$expected" | sed 's/[[:space:]]*$//')
        actual_norm=$(echo "$actual" | sed 's/[[:space:]]*$//')

        if [[ "$actual_norm" == "$expected_norm" ]]; then
            echo -e "  Test $tc_num: ${GREEN}PASS${NC}"
            ((PASS++))
        else
            echo -e "  Test $tc_num: ${RED}FAIL${NC}"
            echo "    Expected:"
            echo "$expected_norm" | sed 's/^/      /'
            echo "    Got:"
            echo "$actual_norm" | sed 's/^/      /'
            ((FAIL++))
        fi
    done
    echo ""
done

# ---- Cleanup ----
rm -f solution_go solution_zig

# ---- Summary ----
TOTAL=$((PASS + FAIL + SKIP))
echo -e "${YELLOW}=== Summary ===${NC}"
echo -e "  Total: $TOTAL | ${GREEN}Pass: $PASS${NC} | ${RED}Fail: $FAIL${NC} | Skip: $SKIP"

if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
