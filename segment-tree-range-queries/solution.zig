// Segment Tree - Range Sum Queries with Point Updates
//
// Approach:
//   - Build a recursive segment tree stored in a 1-indexed array of size 4*N.
//   - Node v covers the segment [tl, tr].
//   - Left child = 2*v, right child = 2*v+1.
//   - Each node stores the sum of its segment as i64 (to handle large sums).
//   - Update: traverse to the leaf and propagate sums back up -> O(log N).
//   - Query: split the range across children recursively -> O(log N).
//
// Uses Zig 0.15 buffered streaming I/O for fast input/output.

const std = @import("std");

const MAX_N = 200_001;

var tree: [4 * MAX_N]i64 = undefined;
var arr: [MAX_N]i64 = undefined;

// Buffers for streaming I/O
var read_buf: [1 << 16]u8 = undefined;
var write_buf: [1 << 16]u8 = undefined;

/// Build the segment tree recursively from array `arr`.
/// v = current node index (1-based), tl..tr = segment covered (0-indexed).
fn build(v: usize, tl: usize, tr: usize) void {
    if (tl == tr) {
        tree[v] = arr[tl];
        return;
    }
    const tm = (tl + tr) / 2;
    build(2 * v, tl, tm);
    build(2 * v + 1, tm + 1, tr);
    tree[v] = tree[2 * v] + tree[2 * v + 1];
}

/// Update position `pos` to value `val`, propagate sums upward.
fn doUpdate(v: usize, tl: usize, tr: usize, pos: usize, val: i64) void {
    if (tl == tr) {
        tree[v] = val;
        return;
    }
    const tm = (tl + tr) / 2;
    if (pos <= tm) {
        doUpdate(2 * v, tl, tm, pos, val);
    } else {
        doUpdate(2 * v + 1, tm + 1, tr, pos, val);
    }
    tree[v] = tree[2 * v] + tree[2 * v + 1];
}

/// Query the sum of elements in range [l, r] (0-indexed).
fn doQuery(v: usize, tl: usize, tr: usize, l: usize, r: usize) i64 {
    if (l > r) {
        return 0;
    }
    if (l == tl and r == tr) {
        return tree[v];
    }
    const tm = (tl + tr) / 2;
    const left_r = @min(r, tm);
    const right_l = @max(l, tm + 1);
    return doQuery(2 * v, tl, tm, l, left_r) + doQuery(2 * v + 1, tm + 1, tr, right_l, r);
}

/// Parse the next integer from the buffered reader, skipping whitespace.
fn readInt(reader: *std.Io.Reader) !i64 {
    // Skip whitespace
    var byte: u8 = 0;
    while (true) {
        byte = reader.takeByte() catch return error.ReadFailed;
        if (byte != ' ' and byte != '\n' and byte != '\r' and byte != '\t') break;
    }

    var negative = false;
    if (byte == '-') {
        negative = true;
        byte = try reader.takeByte();
    }

    var result: i64 = 0;
    while (byte >= '0' and byte <= '9') {
        result = result * 10 + @as(i64, byte - '0');
        byte = reader.takeByte() catch 0;
        if (byte == 0) break;
    }

    if (negative) result = -result;
    return result;
}

pub fn main() !void {
    // Set up buffered streaming I/O (Zig 0.15 API)
    var in_stream = std.fs.File.stdin().readerStreaming(&read_buf);
    var out_stream = std.fs.File.stdout().writerStreaming(&write_buf);
    const reader = &in_stream.interface;
    const writer = &out_stream.interface;

    // Read N and Q
    const n: usize = @intCast(try readInt(reader));
    const q_count: usize = @intCast(try readInt(reader));

    // Read the initial array (0-indexed)
    for (0..n) |i| {
        arr[i] = try readInt(reader);
    }

    // Build the segment tree over [0, n-1]
    build(1, 0, n - 1);

    // Process queries
    for (0..q_count) |_| {
        const qtype: usize = @intCast(try readInt(reader));

        if (qtype == 1) {
            // Update: position i (1-indexed) -> convert to 0-indexed
            const idx: usize = @intCast(try readInt(reader));
            const val: i64 = try readInt(reader);
            doUpdate(1, 0, n - 1, idx - 1, val);
        } else {
            // Query: range [l, r] (1-indexed) -> convert to 0-indexed
            const l: usize = @intCast(try readInt(reader));
            const r: usize = @intCast(try readInt(reader));
            const result = doQuery(1, 0, n - 1, l - 1, r - 1);
            try writer.print("{}\n", .{result});
        }
    }

    try out_stream.interface.flush();
}
