import sys

MOD = 10**9 + 7

def mat_mul(a, b):
    """Multiply two 2x2 matrices modulo MOD."""
    return [
        [(a[0][0] * b[0][0] + a[0][1] * b[1][0]) % MOD,
         (a[0][0] * b[0][1] + a[0][1] * b[1][1]) % MOD],
        [(a[1][0] * b[0][0] + a[1][1] * b[1][0]) % MOD,
         (a[1][0] * b[0][1] + a[1][1] * b[1][1]) % MOD],
    ]

def mat_pow(m, n):
    """Compute m^n using repeated squaring (binary exponentiation)."""
    # Start with the 2x2 identity matrix
    result = [[1, 0], [0, 1]]
    while n > 0:
        if n & 1:
            result = mat_mul(result, m)
        m = mat_mul(m, m)
        n >>= 1
    return result

def fibonacci(n):
    """Compute F(n) mod 10^9+7 using matrix exponentiation in O(log n)."""
    if n == 0:
        return 0
    if n == 1:
        return 1
    # The transformation matrix: [[1,1],[1,0]]^n gives F(n) at position [0][1]
    base = [[1, 1], [1, 0]]
    result = mat_pow(base, n)
    return result[0][1]

def main():
    n = int(sys.stdin.readline().strip())
    print(fibonacci(n))

if __name__ == "__main__":
    main()
