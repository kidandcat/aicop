# Fibonacci with Matrix Exponentiation

**Source:** Classic problem (Codeforces / SPOJ FIBOFAST)

## Problem Statement

Given a number **N**, compute the N-th Fibonacci number modulo 10^9 + 7.

The Fibonacci sequence is defined as:
- F(0) = 0
- F(1) = 1
- F(n) = F(n-1) + F(n-2) for n >= 2

## Constraints

- 0 <= N <= 10^18

## Input Format

A single line containing a single integer N.

## Output Format

A single integer: F(N) mod (10^9 + 7).

## Examples

| Input | Output |
|---|---|
| 0 | 0 |
| 1 | 1 |
| 10 | 55 |
| 1000000000000000000 | 209783453 |

## Algorithm: Matrix Exponentiation

The naive recursive or iterative approach to compute Fibonacci numbers runs in O(N) time, which is far too slow when N can be up to 10^18.

The key insight is that the Fibonacci recurrence can be expressed as a matrix multiplication:

```
| F(n+1) |   | 1  1 |   | F(n)   |
| F(n)   | = | 1  0 | * | F(n-1) |
```

By induction, this gives us:

```
| F(n+1)  F(n)   |   | 1  1 |^n
| F(n)    F(n-1) | = | 1  0 |
```

So computing F(n) reduces to computing the n-th power of the 2x2 matrix `[[1, 1], [1, 0]]` and reading the element at position [0][1] (or equivalently [1][0]).

### Fast Matrix Exponentiation (Repeated Squaring)

We compute M^n using the binary exponentiation technique:

1. Start with the identity matrix as the result.
2. While n > 0:
   - If n is odd, multiply the result by M.
   - Square M.
   - Divide n by 2 (integer division).

This runs in **O(log n)** time with **O(1)** space (since we only work with 2x2 matrices).

### 2x2 Matrix Multiplication (mod p)

For matrices A and B, the product C = A * B is:

```
C[0][0] = A[0][0]*B[0][0] + A[0][1]*B[1][0]
C[0][1] = A[0][0]*B[0][1] + A[0][1]*B[1][1]
C[1][0] = A[1][0]*B[0][0] + A[1][1]*B[1][0]
C[1][1] = A[1][0]*B[0][1] + A[1][1]*B[1][1]
```

All arithmetic is performed modulo 10^9 + 7 to prevent overflow and produce the final answer.

### Complexity

- **Time:** O(log N) matrix multiplications, each O(1) for 2x2 matrices = **O(log N)**
- **Space:** O(1) - only a constant number of 2x2 matrices

### Implementation Notes

- Handle N=0 and N=1 as special/base cases.
- In languages with fixed-width integers (Go, Zig), intermediate multiplication products of two values up to ~10^9 can reach ~10^18, which fits in 64-bit integers. However, to be safe (especially in Zig), casting to 128-bit for intermediate products is recommended.

## Solutions

- [solution.py](solution.py) - Python
- [solution.rb](solution.rb) - Ruby
- [solution.go](solution.go) - Go
- [solution.zig](solution.zig) - Zig

## Testing

Run all tests:

```bash
./test.sh
```
