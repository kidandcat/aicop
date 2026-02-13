# Dijkstra's Shortest Path

## Problem Statement

Given a weighted directed graph with **N** nodes and **M** edges, find the shortest path from node 1 to node N. If no path exists, output `-1`.

## Input Format

- First line: two integers `N M` — the number of nodes and edges.
- Next `M` lines: three integers `u v w` — a directed edge from node `u` to node `v` with weight `w`.

Nodes are **1-indexed**.

## Output Format

A single integer: the shortest distance from node 1 to node N, or `-1` if node N is unreachable from node 1.

## Constraints

| Parameter | Range |
|-----------|-------|
| N (nodes) | 1 <= N <= 100,000 |
| M (edges) | 1 <= M <= 200,000 |
| w (weight)| 1 <= w <= 10^9 |

Since edge weights can be up to 10^9 and paths can have up to N-1 edges, the maximum possible shortest distance is approximately 10^14, which exceeds the range of 32-bit integers. All solutions must use **64-bit integers** for distances.

## Examples

### Example 1

**Input:**
```
5 6
1 2 2
1 3 5
2 3 1
2 4 7
3 4 3
4 5 1
```

**Output:**
```
7
```

**Explanation:** The shortest path is 1 -> 2 -> 3 -> 4 -> 5 with cost 2 + 1 + 3 + 1 = 7. The direct path 1 -> 3 -> 4 -> 5 costs 5 + 3 + 1 = 9, which is longer.

### Example 2

**Input:**
```
3 1
1 2 5
```

**Output:**
```
-1
```

**Explanation:** There is no path from node 1 to node 3. The only edge goes from 1 to 2.

## Algorithm: Dijkstra with Binary Heap

Dijkstra's algorithm finds the shortest path from a single source to all other nodes in a graph with **non-negative** edge weights. The key insight is a greedy one: among all unvisited nodes, the one with the smallest tentative distance is guaranteed to have its final shortest distance already determined.

### Steps

1. **Initialize** distances: `dist[1] = 0`, `dist[v] = infinity` for all other nodes.
2. **Push** `(0, 1)` into a min-heap (priority queue ordered by distance).
3. **While** the heap is non-empty:
   a. Pop the node `u` with the smallest distance `d`.
   b. If `d > dist[u]`, skip it (lazy deletion — this entry is outdated).
   c. For each neighbor `v` of `u` with edge weight `w`:
      - If `dist[u] + w < dist[v]`, update `dist[v] = dist[u] + w` and push `(dist[v], v)` into the heap.
4. **Return** `dist[N]` (or `-1` if it remains infinity).

### Complexity

- **Time:** O((N + M) log N) — each node is processed at most once, and each edge triggers at most one heap insertion. Each heap operation costs O(log N).
- **Space:** O(N + M) — for the adjacency list and distance array.

### Why Lazy Deletion?

Instead of implementing a decrease-key operation (which is complex and often slower in practice), we simply push a new entry into the heap whenever we find a shorter path. When we pop an entry whose distance is larger than the already-known shortest distance, we skip it. This approach is simpler and performs well in practice.

## Solutions

| File | Language | Notes |
|------|----------|-------|
| `solution.py` | Python | Uses `heapq` for the min-heap |
| `solution.rb` | Ruby | Custom binary heap implementation |
| `solution.go` | Go | Uses `container/heap` interface |
| `solution.zig` | Zig | Uses `std.PriorityQueue` |

## Testing

Run `./test.sh` to execute all solutions against the test suite.
