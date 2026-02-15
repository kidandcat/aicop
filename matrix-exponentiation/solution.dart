// Compute N-th Fibonacci number mod 10^9+7 using matrix exponentiation.
// F(0) = 0, F(1) = 1, F(N) = F(N-1) + F(N-2)
//
// Uses the identity:
//   |F(n+1)  F(n)  |   |1 1|^n
//   |F(n)    F(n-1)| = |1 0|
//
// Time: O(log N), Space: O(1)

import 'dart:io';

const int mod = 1000000007;

/// A 2x2 matrix stored as a flat list: [a00, a01, a10, a11].
typedef Matrix = List<int>;

/// Multiplies two 2x2 matrices modulo [mod].
///
/// Products of values < 10^9 give at most ~10^18, which fits in a 64-bit int.
/// A single `% mod` after each sum is sufficient.
Matrix matMul(Matrix a, Matrix b) {
  return [
    (a[0] * b[0] + a[1] * b[2]) % mod,
    (a[0] * b[1] + a[1] * b[3]) % mod,
    (a[2] * b[0] + a[3] * b[2]) % mod,
    (a[2] * b[1] + a[3] * b[3]) % mod,
  ];
}

/// Computes [m]^[n] using binary exponentiation.
Matrix matPow(Matrix m, int n) {
  var result = [1, 0, 0, 1]; // identity
  while (n > 0) {
    if (n & 1 == 1) {
      result = matMul(result, m);
    }
    m = matMul(m, m);
    n >>= 1;
  }
  return result;
}

/// Returns F([n]) mod 10^9+7 in O(log n).
int fibonacci(int n) {
  if (n == 0) return 0;
  if (n == 1) return 1;
  final base = [1, 1, 1, 0];
  final result = matPow(base, n);
  return result[1]; // [0][1]
}

void main() {
  final n = int.parse(stdin.readLineSync()!.trim());
  print(fibonacci(n));
}
