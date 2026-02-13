# Segment tree with point updates and range sum queries.
#
# Input:  line 1 = "N Q"
#         line 2 = N space-separated integers (initial values)
#         next Q lines:
#           "1 i v" -> update: set position i to value v  (1-indexed)
#           "2 l r" -> query: sum of elements in [l, r]   (1-indexed, inclusive)
# Output: one line per query with the answer
#
# Array-based segment tree with 1-indexed internal nodes.
# Uses Int64 for sums to handle large accumulated values.

# ──────────────────────────────────────────────────────────
# Segment tree stored in a flat array of size 4N.
# Node 1 is the root covering [1, n].
# Children of node k: left = 2k, right = 2k+1.
# ──────────────────────────────────────────────────────────

mutable struct SegTree
    n::Int
    tree::Vector{Int64}
end

"""
    build!(st, arr, node, lo, hi)

Recursively build the segment tree from `arr[lo:hi]`.
"""
function build!(st::SegTree, arr::Vector{Int64}, node::Int, lo::Int, hi::Int)
    if lo == hi
        @inbounds st.tree[node] = arr[lo]
        return
    end
    mid = (lo + hi) >> 1
    build!(st, arr, 2node, lo, mid)
    build!(st, arr, 2node + 1, mid + 1, hi)
    @inbounds st.tree[node] = st.tree[2node] + st.tree[2node + 1]
end

"""
    SegTree(arr::Vector{Int64})

Construct a segment tree over the given 1-indexed array.
"""
function SegTree(arr::Vector{Int64})
    n = length(arr)
    tree = zeros(Int64, 4n)
    st = SegTree(n, tree)
    n > 0 && build!(st, arr, 1, 1, n)
    st
end

"""
    update!(st, node, lo, hi, pos, val)

Point update: set `arr[pos] = val` and propagate sums upward.
"""
function update!(st::SegTree, node::Int, lo::Int, hi::Int, pos::Int, val::Int64)
    if lo == hi
        @inbounds st.tree[node] = val
        return
    end
    mid = (lo + hi) >> 1
    if pos <= mid
        update!(st, 2node, lo, mid, pos, val)
    else
        update!(st, 2node + 1, mid + 1, hi, pos, val)
    end
    @inbounds st.tree[node] = st.tree[2node] + st.tree[2node + 1]
end

"""
    query(st, node, lo, hi, ql, qr) -> Int64

Range sum query over [ql, qr].
"""
function query(st::SegTree, node::Int, lo::Int, hi::Int, ql::Int, qr::Int)::Int64
    if ql > hi || qr < lo
        return Int64(0)
    end
    if ql <= lo && hi <= qr
        @inbounds return st.tree[node]
    end
    mid = (lo + hi) >> 1
    query(st, 2node, lo, mid, ql, qr) + query(st, 2node + 1, mid + 1, hi, ql, qr)
end

# Convenience wrappers using multiple dispatch
update!(st::SegTree, pos::Int, val::Int64) = update!(st, 1, 1, st.n, pos, val)
query(st::SegTree, l::Int, r::Int) = query(st, 1, 1, st.n, l, r)

function main()
    data = read(stdin, String)
    tokens = split(data)
    idx = 1

    n = parse(Int, tokens[idx]); idx += 1
    q = parse(Int, tokens[idx]); idx += 1

    arr = Vector{Int64}(undef, n)
    for i in 1:n
        @inbounds arr[i] = parse(Int64, tokens[idx]); idx += 1
    end

    st = SegTree(arr)

    # Pre-allocate output buffer for fast I/O
    io = IOBuffer()

    for _ in 1:q
        op = parse(Int, tokens[idx]); idx += 1
        if op == 1
            # Point update: set position i to value v
            i = parse(Int, tokens[idx]); idx += 1
            v = parse(Int64, tokens[idx]); idx += 1
            update!(st, i, v)
        else
            # Range sum query: [l, r]
            l = parse(Int, tokens[idx]); idx += 1
            r = parse(Int, tokens[idx]); idx += 1
            println(io, query(st, l, r))
        end
    end

    write(stdout, take!(io))
end

main()
