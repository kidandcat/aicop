# Range Sum Queries with Updates

Classic competitive programming problem using a **Segment Tree** data structure.

## Problem Statement

Given an array of **N** integers, process **Q** queries of two types:

- **Type 1** (`1 i v`): Update the value at position `i` to `v` (1-indexed).
- **Type 2** (`2 l r`): Query the sum of elements in the range `[l, r]` (1-indexed, inclusive).

## Constraints

- 1 <= N, Q <= 200,000
- 1 <= a_i, v <= 10^9
- 1 <= l <= r <= N

## Input Format

```
N Q
a_1 a_2 ... a_N
<Q lines of queries, each either "1 i v" or "2 l r">
```

## Output Format

For each **Type 2** query, output the sum on a separate line.

## Examples

### Example 1

**Input:**
```
5 5
1 2 3 4 5
2 1 3
1 2 5
2 1 3
2 1 5
2 3 5
```

**Output:**
```
6
9
18
12
```

**Explanation:**
- Initial array: `[1, 2, 3, 4, 5]`
- `2 1 3`: sum of positions 1..3 = 1 + 2 + 3 = **6**
- `1 2 5`: set position 2 to 5, array becomes `[1, 5, 3, 4, 5]`
- `2 1 3`: sum of positions 1..3 = 1 + 5 + 3 = **9**
- `2 1 5`: sum of positions 1..5 = 1 + 5 + 3 + 4 + 5 = **18**
- `2 3 5`: sum of positions 3..5 = 3 + 4 + 5 = **12**

### Example 2

**Input:**
```
1 2
1000000000
2 1 1
1 1 999999999
```

**Output:**
```
1000000000
```

**Explanation:**
- Single element array `[1000000000]`.
- Query sum of `[1,1]` = **1000000000**.
- Update position 1 to 999999999 (no further queries).

### Example 3

**Input:**
```
3 4
10 20 30
2 1 3
1 1 100
1 3 200
2 1 3
```

**Output:**
```
60
320
```

**Explanation:**
- Initial array: `[10, 20, 30]`
- `2 1 3` -> 10+20+30 = **60**
- `1 1 100` -> array becomes `[100, 20, 30]`
- `1 3 200` -> array becomes `[100, 20, 200]`
- `2 1 3` -> 100+20+200 = **320**

## Algorithm: Segment Tree

A **Segment Tree** is a binary tree data structure used for storing information about intervals (segments) of an array. It allows:

- **Point updates** in O(log N)
- **Range queries** in O(log N)
- **Build** in O(N)

### Structure

The tree is stored as a flat array of size `4*N`. Node at index `v` has:
- Left child at `2*v`
- Right child at `2*v + 1`

Each node stores the sum of elements in its segment.

### Build

Recursively divide the array in half until reaching single elements (leaves). Each internal node stores the sum of its two children.

```
build(v, tl, tr):
    if tl == tr:
        tree[v] = a[tl]
    else:
        tm = (tl + tr) / 2
        build(2*v, tl, tm)
        build(2*v+1, tm+1, tr)
        tree[v] = tree[2*v] + tree[2*v+1]
```

### Update

To update position `pos` to value `val`, traverse from root to the leaf, then propagate the change back up.

```
update(v, tl, tr, pos, val):
    if tl == tr:
        tree[v] = val
    else:
        tm = (tl + tr) / 2
        if pos <= tm:
            update(2*v, tl, tm, pos, val)
        else:
            update(2*v+1, tm+1, tr, pos, val)
        tree[v] = tree[2*v] + tree[2*v+1]
```

### Query

To query the sum in range `[l, r]`, recursively split the query range across the tree.

```
query(v, tl, tr, l, r):
    if l > r:
        return 0
    if l == tl and r == tr:
        return tree[v]
    tm = (tl + tr) / 2
    return query(2*v, tl, tm, l, min(r, tm)) +
           query(2*v+1, tm+1, tr, max(l, tm+1), r)
```

### Complexity

| Operation | Time      | Space |
|-----------|-----------|-------|
| Build     | O(N)      | O(N)  |
| Update    | O(log N)  | -     |
| Query     | O(log N)  | -     |
| Total     | O(N + Q log N) | O(N) |

## Solutions

| File          | Language | Notes                          |
|---------------|----------|--------------------------------|
| solution.py   | Python   | Recursive, sys.stdin for I/O   |
| solution.rb   | Ruby     | Recursive, $stdin for I/O      |
| solution.go   | Go       | Recursive, bufio.Scanner       |
| solution.zig  | Zig      | Recursive, buffered I/O        |

## Testing

Run all tests with:

```bash
./test.sh
```

This runs each solution against multiple test cases and reports pass/fail.
