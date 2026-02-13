const std = @import("std");

const MOD: u64 = 1_000_000_007;

/// A 2x2 matrix with u64 elements.
const Matrix = [2][2]u64;

/// Multiply two 2x2 matrices modulo MOD.
/// We cast to u128 for intermediate products to avoid overflow,
/// since two u64 values up to ~10^9 multiplied can reach ~10^18,
/// and summing two such products would overflow u64.
fn matMul(a: Matrix, b: Matrix) Matrix {
    var c: Matrix = undefined;
    c[0][0] = @intCast((@as(u128, a[0][0]) * @as(u128, b[0][0]) + @as(u128, a[0][1]) * @as(u128, b[1][0])) % MOD);
    c[0][1] = @intCast((@as(u128, a[0][0]) * @as(u128, b[0][1]) + @as(u128, a[0][1]) * @as(u128, b[1][1])) % MOD);
    c[1][0] = @intCast((@as(u128, a[1][0]) * @as(u128, b[0][0]) + @as(u128, a[1][1]) * @as(u128, b[1][0])) % MOD);
    c[1][1] = @intCast((@as(u128, a[1][0]) * @as(u128, b[0][1]) + @as(u128, a[1][1]) * @as(u128, b[1][1])) % MOD);
    return c;
}

/// Compute m^n using repeated squaring (binary exponentiation).
fn matPow(mat: Matrix, exp: u64) Matrix {
    var m = mat;
    var n = exp;
    // Start with the 2x2 identity matrix
    var result: Matrix = .{ .{ 1, 0 }, .{ 0, 1 } };
    while (n > 0) {
        if (n & 1 == 1) {
            result = matMul(result, m);
        }
        m = matMul(m, m);
        n >>= 1;
    }
    return result;
}

/// Compute F(n) mod 10^9+7 using matrix exponentiation in O(log n).
fn fibonacci(n: u64) u64 {
    if (n == 0) return 0;
    if (n == 1) return 1;
    // The transformation matrix: [[1,1],[1,0]]^n gives F(n) at position [0][1]
    const base: Matrix = .{ .{ 1, 1 }, .{ 1, 0 } };
    const result = matPow(base, n);
    return result[0][1];
}

pub fn main() !void {
    // Read input from stdin using File API (Zig 0.15+)
    const stdin_file = std.fs.File.stdin();
    var read_buf: [64]u8 = undefined;
    const bytes_read = stdin_file.readAll(&read_buf) catch return;
    const input = std.mem.trimRight(u8, read_buf[0..bytes_read], &[_]u8{ '\r', '\n', ' ' });
    if (input.len == 0) return;
    const n = std.fmt.parseInt(u64, input, 10) catch return;

    // Write output to stdout
    const stdout_file = std.fs.File.stdout();
    var write_buf: [64]u8 = undefined;
    const output = std.fmt.bufPrint(&write_buf, "{}\n", .{fibonacci(n)}) catch return;
    _ = stdout_file.write(output) catch return;
}
