# KMP (Knuth-Morris-Pratt) string matching.
#
# Input:  line 1 = text T, line 2 = pattern P
# Output: line 1 = number of matches
#         line 2 = space-separated 0-based starting positions (or empty line)
#
# Julia strings are 1-indexed internally; we convert to 0-based on output.

"""
    build_lps(pattern::AbstractString) -> Vector{Int}

Build the Longest Proper Prefix which is also Suffix (LPS / failure function)
array for the KMP algorithm. Returns a 1-indexed vector of length |pattern|.
"""
function build_lps(pattern::AbstractString)::Vector{Int}
    m = length(pattern)
    lps = zeros(Int, m)
    # lps[1] is always 0
    len = 0   # length of the previous longest prefix-suffix
    i = 2
    while i <= m
        if pattern[i] == pattern[len + 1]
            len += 1
            lps[i] = len
            i += 1
        elseif len > 0
            len = lps[len]
        else
            lps[i] = 0
            i += 1
        end
    end
    lps
end

"""
    kmp_search(text::AbstractString, pattern::AbstractString) -> Vector{Int}

Return a vector of 0-based positions where `pattern` occurs in `text`.
Uses the KMP algorithm with the LPS array for O(N+M) matching.
"""
function kmp_search(text::AbstractString, pattern::AbstractString)::Vector{Int}
    n = length(text)
    m = length(pattern)
    positions = Int[]

    m == 0 && return positions  # empty pattern matches nowhere (by convention)

    lps = build_lps(pattern)

    i = 1  # index in text   (1-based)
    j = 0  # number of matched chars in pattern

    while i <= n
        if text[i] == pattern[j + 1]
            i += 1
            j += 1
        end
        if j == m
            push!(positions, i - j - 1)  # convert to 0-based
            j = lps[j]
        elseif i <= n && text[i] != pattern[j + 1]
            if j > 0
                j = lps[j]
            else
                i += 1
            end
        end
    end
    positions
end

function main()
    text = readline(stdin)
    pattern = readline(stdin)
    matches = kmp_search(text, pattern)
    println(length(matches))
    println(join(matches, ' '))
end

main()
