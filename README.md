# AICOP — AI Coding Capabilities

> How well does AI write code? A comparative analysis of Claude's competitive programming solutions across **11 languages** and **5 algorithmic challenges**.

**[View the full interactive report](https://kidandcat.github.io/aicop/)**

## Overview

55 solutions. 6,400+ lines of code. From Python to x86-64 Assembly.

This project evaluates Claude's ability to write complex, optimized programs across the full spectrum of programming languages — measuring idioms, performance, memory management, and code quality.

## Language Tier List

| Tier | Languages | Score |
|------|-----------|-------|
| S — Expert | Python, C++ | 9/10 |
| A — Strong | Rust, Julia, C | 8–8.5/10 |
| B — Competent | Go, Factor | 7–7.5/10 |
| C — Adequate | TypeScript, Zig, Ruby | 6–6.5/10 |
| D — Limited | Assembly x86-64 | 5.5/10 |

## Problems

| Problem | Complexity | What it tests |
|---------|-----------|---------------|
| Dijkstra's Shortest Path | O((N+M) log N) | Heap usage, graph representation |
| KMP String Matching | O(N+M) | String handling, prefix functions |
| Longest Increasing Subsequence | O(N log N) | Binary search, stdlib usage |
| Matrix Exponentiation | O(log N) | Overflow handling, matrix math |
| Segment Tree Range Queries | O(N + Q log N) | Data structure encapsulation, buffered I/O |

## Key Findings

- **C++ shatters the verbosity myth** — second most concise language at just 285 total lines
- **Translation bias persists** — all 55 implementations share identical algorithmic structure and variable names
- **Rust delivers** — zero-cost abstractions, memory safety, 289 lines
- **TypeScript disappoints** — the type system is its defining feature, yet solutions read like JavaScript with annotations
- **Assembly at scale** — 555 lines for a Segment Tree in raw x86-64, but Dijkstra was downgraded to O(N²)

## Language Spectrum

Every memory management model is represented:

```
Pure GC ──── GC + tuning ──── Ownership ──── RAII ──── Manual + defer ──── Full manual ──── Static BSS
Python       Go               Rust           C++       Zig                 C                Assembly
Ruby         Julia
TypeScript
Factor
```

## Structure

```
aicop/
├── dijkstra-shortest-path/     # 11 solutions + tests
├── kmp-string-matching/        # 11 solutions + tests
├── longest-increasing-subsequence/
├── matrix-exponentiation/
├── segment-tree-range-queries/
├── docs/                       # Interactive report (GitHub Pages)
└── ANALYSIS.md                 # Full detailed analysis
```

## Running Tests

Each problem directory contains a `test.sh` that validates all language implementations against expected outputs.

```bash
cd dijkstra-shortest-path && bash test.sh
```

## License

MIT
