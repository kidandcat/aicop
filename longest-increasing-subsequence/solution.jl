# Longest Increasing Subsequence (strictly increasing) via patience sorting
# with binary search, O(N log N).
#
# Input:  line 1 = N
#         line 2 = N space-separated integers (may be negative, up to 10^9)
# Output: length of LIS
#
# Uses Julia's built-in `searchsortedfirst` for the binary search step.

"""
    lis_length(a::AbstractVector{<:Integer}) -> Int

Compute the length of the longest strictly increasing subsequence of `a`
using the patience-sorting / tails approach.

`tails[k]` holds the smallest tail element of all increasing subsequences
of length `k` found so far.
"""
function lis_length(a::AbstractVector{<:Integer})::Int
    tails = Int64[]   # maintained in sorted (non-decreasing) order

    for x in a
        # Find the first position in tails that is >= x  (strictly increasing)
        pos = searchsortedfirst(tails, x)
        if pos > length(tails)
            push!(tails, x)
        else
            @inbounds tails[pos] = x
        end
    end

    length(tails)
end

function main()
    data = read(stdin, String)
    tokens = split(data)
    idx = 1
    n = parse(Int, tokens[idx]); idx += 1

    if n == 0
        println(0)
        return
    end

    a = Vector{Int64}(undef, n)
    for i in 1:n
        @inbounds a[i] = parse(Int64, tokens[idx]); idx += 1
    end

    println(lis_length(a))
end

main()
