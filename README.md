# AICOP — AI Coding Capabilities

> How well does AI write code? A comprehensive evaluation of Claude's code generation across **competitive programming** and **real-world web APIs**.

**[View the full interactive report](https://kidandcat.github.io/aicop/)**

## Overview

Two independent challenges. Multiple languages. Thousands of lines of code.

This project evaluates Claude's ability to write complex, optimized programs across the full spectrum of programming languages — measuring idioms, performance, memory management, and code quality.

---

## Challenge 1: Competitive Programming

65 solutions. 7,000+ lines of code. 13 languages from Python to x86-64 Assembly.

## Language Tier List

| Tier | Languages | Score |
|------|-----------|-------|
| S — Expert | Python, C++ | 9/10 |
| A — Strong | Rust, Julia, C | 8–8.5/10 |
| B — Competent | Go, Dart, Factor, Ada | 7–7.5/10 |
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
- **Translation bias persists** — all 65 implementations share identical algorithmic structure and variable names
- **Rust delivers** — zero-cost abstractions, memory safety, 289 lines
- **TypeScript disappoints** — the type system is its defining feature, yet solutions read like JavaScript with annotations
- **Assembly at scale** — 555 lines for a Segment Tree in raw x86-64, but Dijkstra was downgraded to O(N²)

## Language Spectrum

Every memory management model is represented:

```
Pure GC ──── GC + tuning ──── Ownership ──── RAII ──── Manual + defer ──── Full manual ──── Static BSS
Python       Go               Rust           C++       Zig                 C                Assembly
Ruby         Julia                            Ada
TypeScript
Dart
Factor
```

---

## Challenge 2: Booking API

A realistic web application — a **booking management REST API** with authentication, database operations, and business logic validation. Same spec, 4 languages, 46 automated tests each.

### Results

| Language | Tests | Lines | Ratio | Framework |
|----------|-------|-------|-------|-----------|
| TypeScript | 46/46 ✓ | 200 | 1.00x | Express |
| Dart | 46/46 ✓ | 361 | 1.81x | Shelf |
| Go | 46/46 ✓ | 397 | 1.99x | Fiber |
| Rust | 46/46 ✓ | 549 | 2.75x | Axum |

### What it tests

- JWT authentication & password hashing
- SQLite database operations with parameterized queries
- RESTful routing with middleware
- Business logic: booking overlap validation
- Error handling and HTTP status codes

### Key takeaway

TypeScript dominates web API development — **2.75x more concise** than Rust for the same functionality. The Node.js/Express ecosystem makes REST APIs remarkably compact.

**[See implementations →](booking-api/)**

---

## Cross-Challenge Conclusions

| Strength | Best Language | Why |
|----------|--------------|-----|
| Web APIs | **TypeScript** | Express ecosystem, minimal boilerplate, 1.00x baseline |
| Pure algorithms | **Rust** | Zero-cost abstractions, memory safety, 289 lines for 5 problems |
| Balance | **Go / Dart** | Good conciseness-to-robustness ratio in both domains |

- **TypeScript** jumped from "Adequate" in competitive programming to dominant in web APIs — the right tool for the right job matters more than raw language capability.
- **Rust** remains excellent but its verbosity cost scales with application complexity (1.06x for algorithms → 2.75x for APIs).
- **Go and Dart** deliver consistent middle-ground performance across both domains.

## Structure

```
aicop/
├── dijkstra-shortest-path/     # 13 solutions + tests
├── kmp-string-matching/        # 13 solutions + tests
├── longest-increasing-subsequence/
├── matrix-exponentiation/
├── segment-tree-range-queries/
├── booking-api/                # REST API challenge (4 languages)
│   ├── typescript/
│   ├── dart/
│   ├── go/
│   └── rust/
├── landing/                    # Interactive report
└── ANALYSIS.md                 # Full detailed analysis
```

## Running Tests

Each problem directory contains a `test.sh` that validates all language implementations against expected outputs.

```bash
# Competitive programming
cd dijkstra-shortest-path && bash test.sh

# Booking API
cd booking-api && bash test.sh
```

## License

MIT
