"""
Dijkstra's Shortest Path — O((N+M) log N)

Finds the shortest path from node 1 to node N in a weighted directed graph.
Uses a min-heap (heapq) with lazy deletion for optimal performance.
"""

import sys
import heapq

INF = 10**18


def solve():
    input_data = sys.stdin.buffer.read().split()
    idx = 0

    n = int(input_data[idx]); idx += 1
    m = int(input_data[idx]); idx += 1

    # Build adjacency list: adj[u] = list of (v, w)
    adj = [[] for _ in range(n + 1)]
    for _ in range(m):
        u = int(input_data[idx]); idx += 1
        v = int(input_data[idx]); idx += 1
        w = int(input_data[idx]); idx += 1
        adj[u].append((v, w))

    # Distance array initialized to infinity
    dist = [INF] * (n + 1)
    dist[1] = 0

    # Min-heap: (distance, node)
    heap = [(0, 1)]

    while heap:
        d, u = heapq.heappop(heap)

        # Lazy deletion: skip if this entry is outdated
        if d > dist[u]:
            continue

        # Relax all outgoing edges from u
        for v, w in adj[u]:
            new_dist = dist[u] + w
            if new_dist < dist[v]:
                dist[v] = new_dist
                heapq.heappush(heap, (new_dist, v))

    # Output result
    print(dist[n] if dist[n] < INF else -1)


if __name__ == "__main__":
    solve()
