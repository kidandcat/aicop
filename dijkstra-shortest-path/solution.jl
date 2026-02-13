# Dijkstra's shortest path from node 1 to node N on a directed weighted graph.
#
# Input:  line 1 = "N M"
#         next M lines = "u v w" (1-indexed directed edge from u to v with weight w)
# Output: shortest distance from 1 to N, or -1 if unreachable
#
# No external packages -- implements a binary min-heap manually.
# Uses Int64 distances with INF sentinel.

const INF = Int64(10)^18

# ──────────────────────────────────────────────────────────
# Min-heap of (distance, node) pairs
# ──────────────────────────────────────────────────────────

struct HeapEntry
    dist::Int64
    node::Int32
end

Base.isless(a::HeapEntry, b::HeapEntry) = a.dist < b.dist

mutable struct MinHeap
    data::Vector{HeapEntry}
    size::Int
end

MinHeap() = MinHeap(HeapEntry[], 0)

function heap_push!(h::MinHeap, entry::HeapEntry)
    h.size += 1
    if h.size > length(h.data)
        push!(h.data, entry)
    else
        @inbounds h.data[h.size] = entry
    end
    _sift_up!(h, h.size)
end

function heap_pop!(h::MinHeap)::HeapEntry
    @inbounds top = h.data[1]
    @inbounds h.data[1] = h.data[h.size]
    h.size -= 1
    h.size > 0 && _sift_down!(h, 1)
    top
end

@inline function _sift_up!(h::MinHeap, i::Int)
    @inbounds while i > 1
        p = i >> 1
        if h.data[i] < h.data[p]
            h.data[i], h.data[p] = h.data[p], h.data[i]
            i = p
        else
            break
        end
    end
end

@inline function _sift_down!(h::MinHeap, i::Int)
    @inbounds while true
        smallest = i
        l = i << 1
        r = l + 1
        if l <= h.size && h.data[l] < h.data[smallest]
            smallest = l
        end
        if r <= h.size && h.data[r] < h.data[smallest]
            smallest = r
        end
        if smallest != i
            h.data[i], h.data[smallest] = h.data[smallest], h.data[i]
            i = smallest
        else
            break
        end
    end
end

# ──────────────────────────────────────────────────────────
# Dijkstra
# ──────────────────────────────────────────────────────────

function dijkstra(n::Int, adj::Vector{Vector{Pair{Int32,Int64}}})::Int64
    dist = fill(INF, n)
    dist[1] = 0

    h = MinHeap()
    heap_push!(h, HeapEntry(Int64(0), Int32(1)))

    while h.size > 0
        cur = heap_pop!(h)
        d, u = cur.dist, Int(cur.node)

        # Skip stale entries
        d > dist[u] && continue

        # Early exit
        u == n && return dist[n]

        for edge in adj[u]
            v, w = Int(edge.first), edge.second
            nd = d + w
            if nd < dist[v]
                dist[v] = nd
                heap_push!(h, HeapEntry(nd, Int32(v)))
            end
        end
    end

    dist[n] == INF ? Int64(-1) : dist[n]
end

function main()
    data = read(stdin, String)
    tokens = split(data)
    idx = 1

    n = parse(Int, tokens[idx]); idx += 1
    m = parse(Int, tokens[idx]); idx += 1

    # Adjacency list using Pair{Int32,Int64} (destination => weight)
    adj = [Vector{Pair{Int32,Int64}}() for _ in 1:n]

    for _ in 1:m
        u = parse(Int32, tokens[idx]); idx += 1
        v = parse(Int32, tokens[idx]); idx += 1
        w = parse(Int64, tokens[idx]); idx += 1
        push!(adj[u], v => w)
    end

    println(dijkstra(n, adj))
end

main()
