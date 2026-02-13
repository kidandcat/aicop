#include <iostream>
#include <array>

using namespace std;

const long long MOD = 1000000007;

using Matrix = array<array<long long, 2>, 2>;

Matrix mat_mul(const Matrix& a, const Matrix& b) {
    Matrix c{};
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 2; j++) {
            for (int k = 0; k < 2; k++) {
                c[i][j] = (c[i][j] + a[i][k] * b[k][j]) % MOD;
            }
        }
    }
    return c;
}

Matrix mat_pow(Matrix m, long long n) {
    Matrix result = {{{1, 0}, {0, 1}}}; // identity
    while (n > 0) {
        if (n & 1) {
            result = mat_mul(result, m);
        }
        m = mat_mul(m, m);
        n >>= 1;
    }
    return result;
}

long long fibonacci(long long n) {
    if (n == 0) return 0;
    if (n == 1) return 1;
    Matrix base = {{{1, 1}, {1, 0}}};
    Matrix result = mat_pow(base, n);
    return result[0][1];
}

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(nullptr);

    long long n;
    cin >> n;
    cout << fibonacci(n) << "\n";
    return 0;
}
