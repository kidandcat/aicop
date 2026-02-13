#!/usr/bin/env bash
#
# Test runner for Longest Increasing Subsequence solutions.
# Compiles (where needed) and runs each solution against multiple test cases.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
TOTAL=0

# --------------------------------------------------------------------------
# Test cases: (name, input, expected_output)
# --------------------------------------------------------------------------
declare -a TEST_NAMES
declare -a TEST_INPUTS
declare -a TEST_EXPECTED

TEST_NAMES+=("Basic example")
TEST_INPUTS+=("6
10 9 2 5 3 7")
TEST_EXPECTED+=("3")

TEST_NAMES+=("Longer sequence")
TEST_INPUTS+=("8
0 1 0 3 2 3 4 5")
TEST_EXPECTED+=("6")

TEST_NAMES+=("Single element")
TEST_INPUTS+=("1
42")
TEST_EXPECTED+=("1")

TEST_NAMES+=("All same elements")
TEST_INPUTS+=("5
7 7 7 7 7")
TEST_EXPECTED+=("1")

TEST_NAMES+=("Already sorted")
TEST_INPUTS+=("5
1 2 3 4 5")
TEST_EXPECTED+=("5")

TEST_NAMES+=("Reverse sorted")
TEST_INPUTS+=("5
5 4 3 2 1")
TEST_EXPECTED+=("1")

TEST_NAMES+=("Two elements increasing")
TEST_INPUTS+=("2
1 2")
TEST_EXPECTED+=("2")

TEST_NAMES+=("Two elements decreasing")
TEST_INPUTS+=("2
2 1")
TEST_EXPECTED+=("1")

TEST_NAMES+=("Negative numbers")
TEST_INPUTS+=("6
-5 -3 -7 -1 0 -2")
TEST_EXPECTED+=("4")

TEST_NAMES+=("Large values mixed")
TEST_INPUTS+=("10
1000000000 -1000000000 500000000 -500000000 0 1 -1 999999999 -999999999 2")
TEST_EXPECTED+=("5")

TEST_NAMES+=("Alternating pattern")
TEST_INPUTS+=("8
1 3 2 4 3 5 4 6")
TEST_EXPECTED+=("5")

NUM_TESTS=${#TEST_NAMES[@]}

# --------------------------------------------------------------------------
# Helper: run a single solution against all test cases
# --------------------------------------------------------------------------
run_tests() {
    local lang="$1"
    local cmd="$2"

    printf "${CYAN}=== %s ===${NC}\n" "$lang"

    for ((i = 0; i < NUM_TESTS; i++)); do
        TOTAL=$((TOTAL + 1))
        local name="${TEST_NAMES[$i]}"
        local input="${TEST_INPUTS[$i]}"
        local expected="${TEST_EXPECTED[$i]}"

        # Run solution, capture output and exit code
        local actual
        actual=$(echo "$input" | eval "$cmd" 2>&1) || true
        # Trim whitespace
        actual=$(echo "$actual" | tr -d '[:space:]')

        if [[ "$actual" == "$expected" ]]; then
            printf "  ${GREEN}PASS${NC} %-30s (got %s)\n" "$name" "$actual"
            PASS=$((PASS + 1))
        else
            printf "  ${RED}FAIL${NC} %-30s (expected %s, got '%s')\n" "$name" "$expected" "$actual"
            FAIL=$((FAIL + 1))
        fi
    done
    echo
}

# --------------------------------------------------------------------------
# Compile Go
# --------------------------------------------------------------------------
printf "${YELLOW}Compiling Go...${NC}\n"
go build -o "$DIR/solution_go" "$DIR/solution.go"
echo "  Done."
echo

# --------------------------------------------------------------------------
# Compile Zig
# --------------------------------------------------------------------------
printf "${YELLOW}Compiling Zig...${NC}\n"
zig build-exe "$DIR/solution.zig" -O ReleaseFast --name solution_zig 2>&1 | head -20 || true
# Zig puts the binary in the current directory
if [[ -f "$DIR/solution_zig" ]]; then
    echo "  Done."
else
    echo "  Warning: Zig compilation may have failed."
fi
echo

# --------------------------------------------------------------------------
# Compile C
# --------------------------------------------------------------------------
printf "${YELLOW}Compiling C...${NC}\n"
if gcc -O2 -o "$DIR/solution_c" "$DIR/solution.c" 2>/dev/null; then
    echo "  Done."
else
    echo "  Warning: C compilation may have failed."
fi
echo

# --------------------------------------------------------------------------
# Compile Assembly (x86-64)
# --------------------------------------------------------------------------
if command -v clang &>/dev/null && arch -x86_64 true 2>/dev/null; then
    printf "${YELLOW}Compiling Assembly...${NC}\n"
    if clang -target x86_64-apple-macos11 -nostdlib -static -e start -o "$DIR/solution_asm" "$DIR/solution.S" 2>/dev/null; then
        echo "  Done."
    else
        echo "  Warning: Assembly compilation may have failed."
    fi
    echo
fi

# --------------------------------------------------------------------------
# Compile TypeScript
# --------------------------------------------------------------------------
if command -v node &>/dev/null && npx tsc --version &>/dev/null; then
    printf "${YELLOW}Compiling TypeScript...${NC}\n"
    if npx tsc --target ES2020 --module commonjs --strict "$DIR/solution.ts" 2>/dev/null; then
        echo "  Done."
    else
        echo "  Warning: TypeScript compilation may have failed."
    fi
    echo
fi

# --------------------------------------------------------------------------
# Compile Rust
# --------------------------------------------------------------------------
if command -v rustc &>/dev/null; then
    printf "${YELLOW}Compiling Rust...${NC}\n"
    if rustc -O -o "$DIR/solution_rs" "$DIR/solution.rs" 2>/dev/null; then
        echo "  Done."
    else
        echo "  Warning: Rust compilation may have failed."
    fi
    echo
fi

# --------------------------------------------------------------------------
# Compile C++
# --------------------------------------------------------------------------
if command -v g++ &>/dev/null; then
    printf "${YELLOW}Compiling C++...${NC}\n"
    if g++ -std=c++17 -O2 -o "$DIR/solution_cpp" "$DIR/solution.cpp" 2>/dev/null; then
        echo "  Done."
    else
        echo "  Warning: C++ compilation may have failed."
    fi
    echo
fi

# --------------------------------------------------------------------------
# Run tests for each language
# --------------------------------------------------------------------------

run_tests "Python" "python3 '$DIR/solution.py'"
run_tests "Ruby"   "ruby '$DIR/solution.rb'"
run_tests "Go"     "'$DIR/solution_go'"

if [[ -f "$DIR/solution_zig" ]]; then
    run_tests "Zig" "'$DIR/solution_zig'"
else
    printf "${RED}Skipping Zig (compilation failed)${NC}\n\n"
fi

if [[ -f "$DIR/solution_c" ]]; then
    run_tests "C" "'$DIR/solution_c'"
else
    printf "${RED}Skipping C (compilation failed)${NC}\n\n"
fi

if [[ -f "$DIR/solution_asm" ]]; then
    run_tests "ASM" "arch -x86_64 '$DIR/solution_asm'"
else
    printf "${RED}Skipping Assembly (compilation failed or not supported)${NC}\n\n"
fi

if command -v julia &>/dev/null; then
    run_tests "Julia" "julia '$DIR/solution.jl'"
else
    printf "${RED}Skipping Julia (julia not found)${NC}\n\n"
fi

if [[ -x "$HOME/factor/factor" ]]; then
    run_tests "Factor" "'$HOME/factor/factor' -script '$DIR/solution.factor'"
else
    printf "${RED}Skipping Factor (~/factor/factor not found)${NC}\n\n"
fi

if [[ -f "$DIR/solution.js" ]]; then
    run_tests "TypeScript" "node '$DIR/solution.js'"
else
    printf "${RED}Skipping TypeScript (compilation failed or tsc not found)${NC}\n\n"
fi

if [[ -f "$DIR/solution_rs" ]]; then
    run_tests "Rust" "'$DIR/solution_rs'"
else
    printf "${RED}Skipping Rust (compilation failed or rustc not found)${NC}\n\n"
fi

if [[ -f "$DIR/solution_cpp" ]]; then
    run_tests "C++" "'$DIR/solution_cpp'"
else
    printf "${RED}Skipping C++ (compilation failed or g++ not found)${NC}\n\n"
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo "==============================="
printf "Total: %d  |  ${GREEN}Pass: %d${NC}  |  ${RED}Fail: %d${NC}\n" "$TOTAL" "$PASS" "$FAIL"
echo "==============================="

# Cleanup compiled binaries
rm -f "$DIR/solution_go" "$DIR/solution_zig" "$DIR/solution_zig.o" "$DIR/solution_c" "$DIR/solution_asm" "$DIR/solution.js" "$DIR/solution_rs" "$DIR/solution_cpp"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
