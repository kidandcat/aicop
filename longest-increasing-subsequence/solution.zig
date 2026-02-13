// Longest Increasing Subsequence - O(N log N) solution using patience sorting.
//
// Algorithm:
//   Maintain a 'tails' array where tails[i] is the smallest tail element of all
//   increasing subsequences of length i+1. For each element, use binary search
//   to find where it belongs in tails:
//     - If it's larger than all elements in tails, append it (extends LIS).
//     - Otherwise, replace the first element >= it (keeps tails as small as possible).
//   The answer is tails.len.

const std = @import("std");

/// Binary search for the leftmost position where tails[pos] >= target.
/// Returns tails_len if target is greater than all elements.
fn lowerBound(tails: []const i64, tails_len: usize, target: i64) usize {
    var lo: usize = 0;
    var hi: usize = tails_len;

    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (tails[mid] < target) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }

    return lo;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Read all input at once from stdin for efficiency with large inputs.
    const stdin_file = std.fs.File.stdin();
    const input_buf = try allocator.alloc(u8, 16 * 1024 * 1024);
    defer allocator.free(input_buf);
    const bytes_read = try stdin_file.readAll(input_buf);
    const input = input_buf[0..bytes_read];

    var it = std.mem.tokenizeAny(u8, input, " \n\r\t");

    // Parse N.
    const n_str = it.next() orelse return;
    const n: usize = std.fmt.parseInt(usize, n_str, 10) catch return;

    // Allocate arrays on the heap.
    const nums = try allocator.alloc(i64, n);
    defer allocator.free(nums);
    const tails = try allocator.alloc(i64, n);
    defer allocator.free(tails);

    // Parse the numbers.
    for (0..n) |i| {
        const token = it.next() orelse return;
        nums[i] = std.fmt.parseInt(i64, token, 10) catch return;
    }

    // Compute LIS length using the patience sorting technique.
    var tails_len: usize = 0;

    for (0..n) |i| {
        const x = nums[i];
        const pos = lowerBound(tails, tails_len, x);

        if (pos == tails_len) {
            // x is larger than all elements in tails; extend the LIS.
            tails[tails_len] = x;
            tails_len += 1;
        } else {
            // Replace tails[pos] with x to keep the tail as small as possible.
            tails[pos] = x;
        }
    }

    // Write the result to stdout.
    const stdout_file = std.fs.File.stdout();
    var out_buf: [4096]u8 = undefined;
    var w = stdout_file.writerStreaming(&out_buf);
    try w.interface.print("{d}\n", .{tails_len});
    try w.interface.flush();
}
