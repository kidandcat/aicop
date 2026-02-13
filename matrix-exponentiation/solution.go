package main

import (
	"fmt"
)

const MOD = 1_000_000_007

// Matrix represents a 2x2 matrix with int64 elements.
type Matrix [2][2]int64

// matMul multiplies two 2x2 matrices modulo MOD.
// We must be careful with overflow: two int64 values up to ~10^9 multiplied
// give ~10^18, which fits in int64 (max ~9.2 * 10^18). Adding two such products
// could overflow, so we take mod after each multiplication before adding.
func matMul(a, b Matrix) Matrix {
	var c Matrix
	c[0][0] = (a[0][0]%MOD*b[0][0]%MOD + a[0][1]%MOD*b[1][0]%MOD) % MOD
	c[0][1] = (a[0][0]%MOD*b[0][1]%MOD + a[0][1]%MOD*b[1][1]%MOD) % MOD
	c[1][0] = (a[1][0]%MOD*b[0][0]%MOD + a[1][1]%MOD*b[1][0]%MOD) % MOD
	c[1][1] = (a[1][0]%MOD*b[0][1]%MOD + a[1][1]%MOD*b[1][1]%MOD) % MOD
	return c
}

// matPow computes m^n using repeated squaring (binary exponentiation).
func matPow(m Matrix, n int64) Matrix {
	// Start with the 2x2 identity matrix
	result := Matrix{{1, 0}, {0, 1}}
	for n > 0 {
		if n&1 == 1 {
			result = matMul(result, m)
		}
		m = matMul(m, m)
		n >>= 1
	}
	return result
}

// fibonacci computes F(n) mod 10^9+7 using matrix exponentiation in O(log n).
func fibonacci(n int64) int64 {
	if n == 0 {
		return 0
	}
	if n == 1 {
		return 1
	}
	// The transformation matrix: [[1,1],[1,0]]^n gives F(n) at position [0][1]
	base := Matrix{{1, 1}, {1, 0}}
	result := matPow(base, n)
	return result[0][1]
}

func main() {
	var n int64
	fmt.Scan(&n)
	fmt.Println(fibonacci(n))
}
