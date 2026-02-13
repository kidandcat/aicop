# KMP String Matching

## Problem Statement

Given a text string **T** and a pattern string **P**, find all occurrences of **P** in **T**. Output the number of occurrences and the 0-indexed starting positions.

## Constraints

| Parameter   | Range                    |
|-------------|--------------------------|
| \|P\|, \|T\| | 1 <= \|P\| <= \|T\| <= 1,000,000 |
| Characters  | lowercase English letters (`a`–`z`) only |

## Input Format

```
T
P
```

- First line: the text string T
- Second line: the pattern string P

## Output Format

```
count
positions
```

- First line: the number of occurrences
- Second line: space-separated 0-indexed starting positions (empty line if no occurrences)

## Examples

### Example 1

**Input:**
```
abababab
abab
```

**Output:**
```
3
0 2 4
```

**Explanation:** The pattern `abab` appears starting at positions 0, 2, and 4. Note that occurrences overlap — the match at position 0 (`abab`abab) and the match at position 2 (ab`abab`ab) share characters.

### Example 2

**Input:**
```
aaaaaa
aa
```

**Output:**
```
5
0 1 2 3 4
```

**Explanation:** The pattern `aa` appears at every position from 0 to 4, with each consecutive pair of `a`s forming a match. This is a maximal overlap case.

### Example 3

**Input:**
```
abcdef
xyz
```

**Output:**
```
0

```

**Explanation:** The pattern `xyz` does not appear in the text, so the count is 0 and the second line is empty.

## Algorithm: Knuth-Morris-Pratt (KMP)

The KMP algorithm finds all occurrences of a pattern in a text in **O(N + M)** time, where N = |T| and M = |P|. It achieves this by preprocessing the pattern to avoid redundant character comparisons.

### Phase 1: Build the Failure Function (LPS Array)

The **LPS array** (Longest Proper Prefix which is also Suffix) is computed for the pattern P. For each position `i` in the pattern, `lps[i]` stores the length of the longest proper prefix of `P[0..i]` that is also a suffix.

```
compute_lps(P):
    m = length(P)
    lps = array of size m, initialized to 0
    length = 0    // length of the previous longest prefix suffix
    i = 1

    while i < m:
        if P[i] == P[length]:
            length += 1
            lps[i] = length
            i += 1
        else:
            if length != 0:
                length = lps[length - 1]    // fall back, don't increment i
            else:
                lps[i] = 0
                i += 1

    return lps
```

**Example:** For pattern `abab`:
- `lps = [0, 0, 1, 2]`
- At position 2, `P[0..2] = "aba"` — the prefix `"a"` is also a suffix, so `lps[2] = 1`.
- At position 3, `P[0..3] = "abab"` — the prefix `"ab"` is also a suffix, so `lps[3] = 2`.

### Phase 2: Search Using the Failure Function

Walk through the text with two pointers: `i` (position in T) and `j` (position in P). When characters match, advance both. When they don't:
- If `j > 0`, use the LPS array to jump: set `j = lps[j - 1]`. This skips characters in the pattern that are known to already match.
- If `j == 0`, simply advance `i`.

When `j` reaches `m` (full pattern matched), record the occurrence at position `i - m`, then set `j = lps[j - 1]` to continue searching for overlapping matches.

```
kmp_search(T, P):
    n = length(T)
    m = length(P)
    lps = compute_lps(P)
    results = []

    i = 0    // index in T
    j = 0    // index in P

    while i < n:
        if T[i] == P[j]:
            i += 1
            j += 1
        if j == m:
            results.append(i - j)
            j = lps[j - 1]
        elif i < n and T[i] != P[j]:
            if j != 0:
                j = lps[j - 1]
            else:
                i += 1

    return results
```

### Complexity

| Phase          | Time   | Space  |
|----------------|--------|--------|
| Build LPS      | O(M)   | O(M)   |
| Search         | O(N)   | O(1)   |
| **Total**      | **O(N + M)** | **O(M)** |

### Why KMP Over Naive Search?

The naive approach (check every starting position) is O(N * M) in the worst case. KMP guarantees O(N + M) because the text pointer `i` never moves backward — when a mismatch occurs, the failure function tells us exactly how far back in the pattern to resume, avoiding re-scanning already matched characters.

## Solutions

| File          | Language | Notes                                     |
|---------------|----------|-------------------------------------------|
| solution.py   | Python   | `sys.stdin.readline` for fast I/O          |
| solution.rb   | Ruby     | `gets.chomp` for input                     |
| solution.go   | Go       | `bufio.Scanner` with large buffer          |
| solution.zig  | Zig      | Buffered stdin reader, manual line parsing |
| solution.c    | C        | `fgets` / manual parsing                   |
| solution.S    | x86-64 Assembly | AT&T syntax, macOS                  |
| solution.jl   | Julia    | Standard I/O                               |
| solution.factor | Factor | Stack-based concatenative language         |
| solution.ts   | TypeScript | Compiled with `tsc`                      |
| solution.rs   | Rust     | Byte-level matching with `BufWriter`       |
| solution.cpp  | C++      | `getline` input, STL `vector`              |

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

Run all tests with:

```bash
./test.sh
```

This runs each solution against multiple test cases and reports pass/fail.
