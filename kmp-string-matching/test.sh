#!/usr/bin/env bash
#
# Test runner for KMP String Matching solutions.
# Runs each solution against a set of test cases and reports pass/fail.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
TOTAL=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Test cases: each defined as input + expected output
# Format: test_name | input_text | input_pattern | expected_output
declare -a TESTS=(
    # Test 1: Overlapping matches (from problem statement)
    "overlapping_abab"
    "abababab"
    "abab"
    "3
0 2 4"

    # Test 2: Maximal overlap with single char (from problem statement)
    "maximal_overlap_aa"
    "aaaaaa"
    "aa"
    "5
0 1 2 3 4"

    # Test 3: No match (from problem statement)
    "no_match"
    "abcdef"
    "xyz"
    "0
"

    # Test 4: Pattern equals text
    "exact_match"
    "hello"
    "hello"
    "1
0"

    # Test 5: Single character match
    "single_char"
    "abcabc"
    "a"
    "2
0 3"

    # Test 6: Pattern at the very end
    "match_at_end"
    "xyzabc"
    "abc"
    "1
3"

    # Test 7: Pattern at the very beginning
    "match_at_start"
    "abcxyz"
    "abc"
    "1
0"

    # Test 8: Multiple non-overlapping matches
    "multiple_non_overlapping"
    "abcXabcXabc"
    "abc"
    "3
0 4 8"

    # Test 9: Long repeated pattern
    "long_repeat"
    "aaaaaaaaaa"
    "aaa"
    "8
0 1 2 3 4 5 6 7"

    # Test 10: Pattern longer overlap
    "complex_overlap"
    "aabaabaab"
    "aab"
    "3
0 3 6"
)

# Number of fields per test case
FIELDS=4

NUM_TESTS=$(( ${#TESTS[@]} / FIELDS ))

# Build Go solution
echo -e "${YELLOW}Building Go solution...${NC}"
cd "$DIR"
go build -o solution_go solution.go 2>&1
echo -e "${YELLOW}Building Zig solution...${NC}"
zig build-exe solution.zig -O ReleaseFast -femit-bin=solution_zig 2>&1
echo -e "${YELLOW}Building C solution...${NC}"
gcc -O2 -o solution_c solution.c 2>&1
if command -v clang &>/dev/null && arch -x86_64 true 2>/dev/null; then
    echo -e "${YELLOW}Building Assembly solution...${NC}"
    clang -target x86_64-apple-macos11 -nostdlib -static -e start -o solution_asm solution.S 2>/dev/null || echo "Assembly compilation failed"
fi
if command -v node &>/dev/null && npx tsc --version &>/dev/null; then
    echo -e "${YELLOW}Compiling TypeScript solution...${NC}"
    npx tsc --target ES2020 --module commonjs --strict solution.ts 2>&1 || echo "TypeScript compilation failed"
fi
if command -v rustc &>/dev/null; then
    echo -e "${YELLOW}Compiling Rust solution...${NC}"
    rustc -O -o solution_rs solution.rs 2>&1 || echo "Rust compilation failed"
fi
if command -v g++ &>/dev/null; then
    echo -e "${YELLOW}Compiling C++ solution...${NC}"
    g++ -std=c++17 -O2 -o solution_cpp solution.cpp 2>&1 || echo "C++ compilation failed"
fi

run_test() {
    local runner_name="$1"
    local runner_cmd="$2"
    local test_name="$3"
    local input_text="$4"
    local input_pattern="$5"
    local expected="$6"

    TOTAL=$((TOTAL + 1))

    local input
    input=$(printf '%s\n%s\n' "$input_text" "$input_pattern")

    local actual
    actual=$(echo "$input" | eval "$runner_cmd" 2>&1) || true

    # Normalize: trim trailing whitespace from each line
    local norm_expected norm_actual
    norm_expected=$(echo "$expected" | sed 's/[[:space:]]*$//')
    norm_actual=$(echo "$actual" | sed 's/[[:space:]]*$//')

    if [ "$norm_expected" = "$norm_actual" ]; then
        echo -e "  ${GREEN}PASS${NC} [$runner_name] $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} [$runner_name] $test_name"
        echo "    Expected: $(echo "$norm_expected" | head -2)"
        echo "    Got:      $(echo "$norm_actual" | head -2)"
        FAIL=$((FAIL + 1))
    fi
}

# Define runners
declare -a RUNNERS=(
    "Python|python3 $DIR/solution.py"
    "Ruby|ruby $DIR/solution.rb"
    "Go|$DIR/solution_go"
    "Zig|$DIR/solution_zig"
    "C|$DIR/solution_c"
    "ASM|arch -x86_64 $DIR/solution_asm"
    "Julia|julia $DIR/solution.jl"
    "Factor|$HOME/factor/factor -script $DIR/solution.factor"
    "TypeScript|node $DIR/solution.js"
    "Rust|$DIR/solution_rs"
    "C++|$DIR/solution_cpp"
)

echo ""
echo "Running KMP String Matching tests..."
echo "======================================"

for (( t = 0; t < NUM_TESTS; t++ )); do
    idx=$((t * FIELDS))
    test_name="${TESTS[$idx]}"
    input_text="${TESTS[$((idx + 1))]}"
    input_pattern="${TESTS[$((idx + 2))]}"
    expected="${TESTS[$((idx + 3))]}"

    echo ""
    echo "Test: $test_name"

    for runner_entry in "${RUNNERS[@]}"; do
        IFS='|' read -r runner_name runner_cmd <<< "$runner_entry"
        run_test "$runner_name" "$runner_cmd" "$test_name" "$input_text" "$input_pattern" "$expected"
    done
done

# Cleanup compiled binaries
rm -f "$DIR/solution_go" "$DIR/solution_zig" "$DIR/solution_zig.o" "$DIR/solution_c" "$DIR/solution_asm" "$DIR/solution.js" "$DIR/solution_rs" "$DIR/solution_cpp"

echo ""
echo "======================================"
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, $TOTAL total"
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
