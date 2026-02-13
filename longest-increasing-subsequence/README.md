# Longest Increasing Subsequence

## Problem Statement

Given an array of **N** integers, find the length of the **longest strictly increasing subsequence** (LIS).

A subsequence is a sequence that can be derived from the array by deleting some or no elements without changing the order of the remaining elements.

## Constraints

- 1 <= N <= 1,000,000
- -10^9 <= a_i <= 10^9

## Input Format

- First line: a single integer **N** (the number of elements).
- Second line: **N** space-separated integers.

## Output Format

A single integer: the length of the longest strictly increasing subsequence.

## Examples

### Example 1

**Input:**
```
6
10 9 2 5 3 7
```

**Output:**
```
3
```

**Explanation:** One valid LIS is `[2, 5, 7]`. Another is `[2, 3, 7]`. Both have length 3.

### Example 2

**Input:**
```
8
0 1 0 3 2 3 4 5
```

**Output:**
```
6
```

**Explanation:** The LIS is `[0, 1, 2, 3, 4, 5]`.

### Example 3 (Edge Case - Single Element)

**Input:**
```
1
42
```

**Output:**
```
1
```

### Example 4 (All Same Elements)

**Input:**
```
5
7 7 7 7 7
```

**Output:**
```
1
```

**Explanation:** Since the subsequence must be *strictly* increasing, repeated elements don't extend it.

### Example 5 (Already Sorted)

**Input:**
```
5
1 2 3 4 5
```

**Output:**
```
5
```

### Example 6 (Reverse Sorted)

**Input:**
```
5
5 4 3 2 1
```

**Output:**
```
1
```

## Algorithm: O(N log N) with Patience Sorting / Binary Search

The naive dynamic programming approach runs in O(N^2), which is too slow for N up to 1,000,000. The optimal solution uses a technique based on **patience sorting** that runs in **O(N log N)**.

### Key Idea

Maintain an array `tails` where `tails[i]` represents the **smallest possible tail element** of all increasing subsequences of length `i + 1` found so far.

**Invariant:** The `tails` array is always sorted in strictly increasing order.

### Algorithm Steps

For each element `x` in the input array:

1. **Binary search** for the leftmost position `pos` in `tails` where `tails[pos] >= x`.
2. If `pos == len(tails)`, then `x` is greater than all elements in `tails`, so **append** `x` (this extends the longest subsequence found so far).
3. Otherwise, **replace** `tails[pos] = x` (this keeps `tails[pos]` as small as possible, potentially allowing longer subsequences later).

After processing all elements, the answer is `len(tails)`.

### Why It Works

- The `tails` array doesn't store the actual LIS; it tracks the *best possible ending values* for subsequences of each length.
- By always keeping the smallest possible tail, we maximize the chance that future elements can extend the subsequence.
- The binary search ensures each element is processed in O(log N) time.

### Complexity

| | Time | Space |
|---|---|---|
| **This algorithm** | O(N log N) | O(N) |
| Naive DP | O(N^2) | O(N) |

## Solutions

| Language | File | Notes |
|---|---|---|
| Python | `solution.py` | Uses `bisect_left` from the `bisect` module |
| Ruby | `solution.rb` | Uses `bsearch_index` for binary search |
| Go | `solution.go` | Uses `sort.SearchInts` |
| Zig | `solution.zig` | Manual binary search with `std.io` |
| C | `solution.c` | Manual binary search |
| x86-64 Assembly | `solution.S` | AT&T syntax, macOS |
| Julia | `solution.jl` | Standard library |
| Factor | `solution.factor` | Stack-based concatenative language |
| TypeScript | `solution.ts` | Custom `lowerBound`, compiled with `tsc` |
| Rust | `solution.rs` | Manual binary search, idiomatic iterators |
| C++ | `solution.cpp` | Uses `std::lower_bound` from `<algorithm>` |

### Build & Run

**TypeScript:**
```bash
tsc --target ES2020 --module commonjs --strict solution.ts
node solution.js < input.txt
```

**Rust:**
```bash
rustc -O -o solution_rs solution.rs
./solution_rs < input.txt
```

**C++:**
```bash
g++ -std=c++17 -O2 -o solution_cpp solution.cpp
./solution_cpp < input.txt
```

**C:**
```bash
gcc -O2 -o solution_c solution.c
./solution_c < input.txt
```

**x86-64 Assembly (macOS):**
```bash
clang -target x86_64-apple-macos11 -nostdlib -static -e start -o solution_asm solution.S
arch -x86_64 ./solution_asm < input.txt
```

**Julia:**
```bash
julia solution.jl < input.txt
```

**Factor:**
```bash
~/factor/factor -script solution.factor < input.txt
```

## Testing

Run the test suite:

```bash
./test.sh
```

This will compile (where needed), run each solution against multiple test cases, and report pass/fail.
