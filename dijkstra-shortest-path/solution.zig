// Dijkstra's Shortest Path — O((N+M) log N)
//
// Finds the shortest path from node 1 to node N in a weighted directed graph.
// Uses std.PriorityQueue for the min-heap with lazy deletion.
//
// Compatible with Zig 0.15+: uses std.fs.File.stdin()/stdout() for I/O,
// unmanaged ArrayList (allocator passed per-call), and reads all input at once.

const std = @import("std");

const INF: i64 = 1_000_000_000_000_000_000; // 10^18

const Edge = struct {
    to: u32,
    weight: i64,
};

const HeapItem = struct {
    dist: i64,
    node: u32,
};

// Comparator for the min-heap: order by distance ascending.
fn lessThan(context: void, a: HeapItem, b: HeapItem) std.math.Order {
    _ = context;
    return std.math.order(a.dist, b.dist);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read all of stdin into memory
    const stdin = std.fs.File.stdin();
    const content = try stdin.readToEndAlloc(allocator, 1024 * 1024 * 64);
    defer allocator.free(content);

    // Tokenize the input by whitespace
    var it = std.mem.tokenizeAny(u8, content, " \n\r\t");

    // Read N and M
    const n = try std.fmt.parseInt(u32, it.next() orelse return error.EndOfStream, 10);
    const m = try std.fmt.parseInt(u32, it.next() orelse return error.EndOfStream, 10);

    // Build adjacency list using unmanaged ArrayLists.
    // In Zig 0.15, ArrayList is unmanaged: allocator is passed to each method.
    const adj_list = try allocator.alloc(std.ArrayList(Edge), n + 1);
    defer {
        for (adj_list) |*list| {
            list.deinit(allocator);
        }
        allocator.free(adj_list);
    }
    // Zero-initialize all lists (they default to empty when zero-initialized)
    for (adj_list) |*list| {
        list.* = .{};
    }

    for (0..m) |_| {
        const u = try std.fmt.parseInt(u32, it.next() orelse return error.EndOfStream, 10);
        const v = try std.fmt.parseInt(u32, it.next() orelse return error.EndOfStream, 10);
        const w = try std.fmt.parseInt(i64, it.next() orelse return error.EndOfStream, 10);
        try adj_list[u].append(allocator, Edge{ .to = v, .weight = w });
    }

    // Distance array initialized to infinity
    const dist = try allocator.alloc(i64, n + 1);
    defer allocator.free(dist);
    @memset(dist, INF);
    dist[1] = 0;

    // Min-heap priority queue
    var pq = std.PriorityQueue(HeapItem, void, lessThan).init(allocator, {});
    defer pq.deinit();
    try pq.add(HeapItem{ .dist = 0, .node = 1 });

    while (pq.count() > 0) {
        const cur = pq.remove();
        const u = cur.node;
        const d = cur.dist;

        // Lazy deletion: skip if this entry is outdated
        if (d > dist[u]) continue;

        // Relax all outgoing edges from u
        for (adj_list[u].items) |edge| {
            const new_dist = dist[u] + edge.weight;
            if (new_dist < dist[edge.to]) {
                dist[edge.to] = new_dist;
                try pq.add(HeapItem{ .dist = new_dist, .node = edge.to });
            }
        }
    }

    // Output result
    const stdout = std.fs.File.stdout();
    var buf: [64]u8 = undefined;
    if (dist[n] < INF) {
        const msg = try std.fmt.bufPrint(&buf, "{d}\n", .{dist[n]});
        _ = try stdout.write(msg);
    } else {
        _ = try stdout.write("-1\n");
    }
}
