/*
 * Compute N-th Fibonacci number mod 10^9+7 using matrix exponentiation.
 * F(0) = 0, F(1) = 1, F(N) = F(N-1) + F(N-2)
 *
 * Uses the identity:
 *   |F(n+1)  F(n)  |   |1 1|^n
 *   |F(n)    F(n-1)| = |1 0|
 *
 * Time: O(log N), Space: O(1)
 */

#include <stdio.h>

#define MOD 1000000007LL

typedef long long ll;
typedef unsigned long long ull;

/* 2x2 matrix */
typedef struct {
    ll m[2][2];
} Mat;

static Mat mat_mul(const Mat *a, const Mat *b) {
    Mat c;
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 2; j++) {
            c.m[i][j] = 0;
            for (int k = 0; k < 2; k++) {
                c.m[i][j] = (c.m[i][j] + a->m[i][k] % MOD * (b->m[k][j] % MOD)) % MOD;
            }
        }
    }
    return c;
}

static Mat mat_pow(Mat base, ull exp) {
    /* Identity matrix */
    Mat result;
    result.m[0][0] = 1; result.m[0][1] = 0;
    result.m[1][0] = 0; result.m[1][1] = 1;

    while (exp > 0) {
        if (exp & 1) {
            result = mat_mul(&result, &base);
        }
        base = mat_mul(&base, &base);
        exp >>= 1;
    }
    return result;
}

int main(void) {
    ull n;
    scanf("%llu", &n);

    if (n == 0) {
        printf("0\n");
        return 0;
    }

    Mat base;
    base.m[0][0] = 1; base.m[0][1] = 1;
    base.m[1][0] = 1; base.m[1][1] = 0;

    Mat result = mat_pow(base, n);

    /* F(n) is at result.m[0][1] (or result.m[1][0]) */
    printf("%lld\n", result.m[0][1]);

    return 0;
}
