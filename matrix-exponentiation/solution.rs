use std::io::{self, Read};

const MOD: u64 = 1_000_000_007;

type Matrix = [[u64; 2]; 2];

fn mat_mul(a: &Matrix, b: &Matrix) -> Matrix {
    [
        [
            (a[0][0] * b[0][0] % MOD + a[0][1] * b[1][0] % MOD) % MOD,
            (a[0][0] * b[0][1] % MOD + a[0][1] * b[1][1] % MOD) % MOD,
        ],
        [
            (a[1][0] * b[0][0] % MOD + a[1][1] * b[1][0] % MOD) % MOD,
            (a[1][0] * b[0][1] % MOD + a[1][1] * b[1][1] % MOD) % MOD,
        ],
    ]
}

fn mat_pow(mut m: Matrix, mut n: u64) -> Matrix {
    let mut result: Matrix = [[1, 0], [0, 1]]; // identity
    while n > 0 {
        if n & 1 == 1 {
            result = mat_mul(&result, &m);
        }
        m = mat_mul(&m, &m);
        n >>= 1;
    }
    result
}

fn fibonacci(n: u64) -> u64 {
    if n == 0 {
        return 0;
    }
    if n == 1 {
        return 1;
    }
    let base: Matrix = [[1, 1], [1, 0]];
    let result = mat_pow(base, n);
    result[0][1]
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let n: u64 = input.trim().parse().unwrap();
    println!("{}", fibonacci(n));
}
