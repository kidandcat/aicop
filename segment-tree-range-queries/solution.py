"""
Segment Tree - Range Sum Queries with Point Updates

Approach:
  - Build a recursive segment tree stored in a 1-indexed array of size 4*N.
  - Node v covers the segment [tl, tr].
  - Left child = 2*v, right child = 2*v+1.
  - Each node stores the sum of its segment.
  - Update: traverse to the leaf and propagate sums back up -> O(log N).
  - Query: split the range across children recursively -> O(log N).

Uses sys.stdin for fast I/O (critical for large inputs in Python).
Uses 64-bit integers natively (Python ints are arbitrary precision).
"""

import sys
input = sys.stdin.readline


def main():
    n, q = map(int, input().split())
    a = list(map(int, input().split()))

    # Segment tree array, 1-indexed, size 4*n is sufficient
    tree = [0] * (4 * n)

    def build(v, tl, tr):
        """Build the segment tree recursively from array a."""
        if tl == tr:
            tree[v] = a[tl]
            return
        tm = (tl + tr) // 2
        build(2 * v, tl, tm)
        build(2 * v + 1, tm + 1, tr)
        tree[v] = tree[2 * v] + tree[2 * v + 1]

    def update(v, tl, tr, pos, val):
        """Update position pos to value val, propagate sums upward."""
        if tl == tr:
            tree[v] = val
            return
        tm = (tl + tr) // 2
        if pos <= tm:
            update(2 * v, tl, tm, pos, val)
        else:
            update(2 * v + 1, tm + 1, tr, pos, val)
        tree[v] = tree[2 * v] + tree[2 * v + 1]

    def query(v, tl, tr, l, r):
        """Query the sum of elements in range [l, r]."""
        if l > r:
            return 0
        if l == tl and r == tr:
            return tree[v]
        tm = (tl + tr) // 2
        left_sum = query(2 * v, tl, tm, l, min(r, tm))
        right_sum = query(2 * v + 1, tm + 1, tr, max(l, tm + 1), r)
        return left_sum + right_sum

    # Build the tree over 0-indexed array positions [0, n-1]
    build(1, 0, n - 1)

    out = []
    for _ in range(q):
        parts = list(map(int, input().split()))
        if parts[0] == 1:
            # Update: position i (1-indexed) -> convert to 0-indexed
            i, v = parts[1], parts[2]
            update(1, 0, n - 1, i - 1, v)
        else:
            # Query: range [l, r] (1-indexed) -> convert to 0-indexed
            l, r = parts[1], parts[2]
            out.append(str(query(1, 0, n - 1, l - 1, r - 1)))

    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
