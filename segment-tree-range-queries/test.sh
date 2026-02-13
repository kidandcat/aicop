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

C_BIN=""
if command -v gcc &>/dev/null; then
    echo "Compiling C..."
    if gcc -O2 -o solution_c solution.c 2>&1; then
        C_BIN="./solution_c"
        echo -e "${GREEN}C compiled successfully${NC}"
    else
        echo -e "${RED}C compilation failed${NC}"
    fi
else
    echo -e "${YELLOW}gcc not found, skipping C${NC}"
fi

ASM_BIN=""
if command -v clang &>/dev/null && arch -x86_64 true 2>/dev/null; then
    echo "Compiling Assembly..."
    if clang -target x86_64-apple-macos11 -nostdlib -static -e start -o solution_asm solution.S 2>/dev/null; then
        ASM_BIN="arch -x86_64 ./solution_asm"
        echo -e "${GREEN}Assembly compiled successfully${NC}"
    else
        echo -e "${RED}Assembly compilation failed${NC}"
    fi
else
    echo -e "${YELLOW}clang not found or x86_64 not supported, skipping Assembly${NC}"
fi

TS_BIN=""
if command -v node &>/dev/null && npx tsc --version &>/dev/null; then
    echo "Compiling TypeScript..."
    if npx tsc --target ES2020 --module commonjs --strict solution.ts 2>/dev/null; then
        TS_BIN="node solution.js"
        echo -e "${GREEN}TypeScript compiled successfully${NC}"
    else
        echo -e "${RED}TypeScript compilation failed${NC}"
    fi
else
    echo -e "${YELLOW}tsc or node not found, skipping TypeScript${NC}"
fi

RS_BIN=""
if command -v rustc &>/dev/null; then
    echo "Compiling Rust..."
    if rustc -O -o solution_rs solution.rs 2>/dev/null; then
        RS_BIN="./solution_rs"
        echo -e "${GREEN}Rust compiled successfully${NC}"
    else
        echo -e "${RED}Rust compilation failed${NC}"
    fi
else
    echo -e "${YELLOW}rustc not found, skipping Rust${NC}"
fi

CPP_BIN=""
if command -v g++ &>/dev/null; then
    echo "Compiling C++..."
    if g++ -std=c++17 -O2 -o solution_cpp solution.cpp 2>/dev/null; then
        CPP_BIN="./solution_cpp"
        echo -e "${GREEN}C++ compiled successfully${NC}"
    else
        echo -e "${RED}C++ compilation failed${NC}"
    fi
else
    echo -e "${YELLOW}g++ not found, skipping C++${NC}"
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

if [[ -n "$C_BIN" ]]; then
    RUNNERS+=("$C_BIN")
    RUNNER_NAMES+=("C")
fi

if [[ -n "$ASM_BIN" ]]; then
    RUNNERS+=("$ASM_BIN")
    RUNNER_NAMES+=("ASM")
fi

if command -v julia &>/dev/null; then
    RUNNERS+=("julia solution.jl")
    RUNNER_NAMES+=("Julia")
else
    echo -e "${YELLOW}Julia not found, skipping${NC}"
fi

if [[ -x "$HOME/factor/factor" ]]; then
    RUNNERS+=("$HOME/factor/factor -script solution.factor")
    RUNNER_NAMES+=("Factor")
else
    echo -e "${YELLOW}Factor not found, skipping${NC}"
fi

if [[ -n "$TS_BIN" ]]; then
    RUNNERS+=("$TS_BIN")
    RUNNER_NAMES+=("TypeScript")
fi

if [[ -n "$RS_BIN" ]]; then
    RUNNERS+=("$RS_BIN")
    RUNNER_NAMES+=("Rust")
fi

if [[ -n "$CPP_BIN" ]]; then
    RUNNERS+=("$CPP_BIN")
    RUNNER_NAMES+=("C++")
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
rm -f solution_go solution_zig solution_c solution_asm solution.js solution_rs solution_cpp

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
