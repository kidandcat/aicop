MOD = 10**9 + 7

# Multiply two 2x2 matrices modulo MOD.
def mat_mul(a, b)
  [
    [(a[0][0] * b[0][0] + a[0][1] * b[1][0]) % MOD,
     (a[0][0] * b[0][1] + a[0][1] * b[1][1]) % MOD],
    [(a[1][0] * b[0][0] + a[1][1] * b[1][0]) % MOD,
     (a[1][0] * b[0][1] + a[1][1] * b[1][1]) % MOD]
  ]
end

# Compute m^n using repeated squaring (binary exponentiation).
def mat_pow(m, n)
  # Start with the 2x2 identity matrix
  result = [[1, 0], [0, 1]]
  while n > 0
    if n & 1 == 1
      result = mat_mul(result, m)
    end
    m = mat_mul(m, m)
    n >>= 1
  end
  result
end

# Compute F(n) mod 10^9+7 using matrix exponentiation in O(log n).
def fibonacci(n)
  return 0 if n == 0
  return 1 if n == 1
  # The transformation matrix: [[1,1],[1,0]]^n gives F(n) at position [0][1]
  base = [[1, 1], [1, 0]]
  result = mat_pow(base, n)
  result[0][1]
end

n = $stdin.readline.strip.to_i
puts fibonacci(n)
