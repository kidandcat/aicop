const MOD = 1000000007n;

type Matrix = [bigint, bigint, bigint, bigint]; // 2x2 stored flat: [a00, a01, a10, a11]

function matMul(a: Matrix, b: Matrix): Matrix {
    return [
        (a[0] * b[0] + a[1] * b[2]) % MOD,
        (a[0] * b[1] + a[1] * b[3]) % MOD,
        (a[2] * b[0] + a[3] * b[2]) % MOD,
        (a[2] * b[1] + a[3] * b[3]) % MOD,
    ];
}

function matPow(m: Matrix, n: bigint): Matrix {
    let result: Matrix = [1n, 0n, 0n, 1n]; // identity
    while (n > 0n) {
        if (n & 1n) {
            result = matMul(result, m);
        }
        m = matMul(m, m);
        n >>= 1n;
    }
    return result;
}

function fibonacci(n: bigint): bigint {
    if (n === 0n) return 0n;
    if (n === 1n) return 1n;
    const base: Matrix = [1n, 1n, 1n, 0n];
    const result = matPow(base, n);
    return result[1]; // [0][1]
}

function solve(input: string): void {
    const n = BigInt(input.trim());
    console.log(fibonacci(n).toString());
}

process.stdin.resume();
process.stdin.setEncoding('utf8');
let inputData = '';
process.stdin.on('data', (chunk: string) => { inputData += chunk; });
process.stdin.on('end', () => { solve(inputData); });
