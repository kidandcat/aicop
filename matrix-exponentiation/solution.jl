# Compute N-th Fibonacci number mod 10^9+7 via matrix exponentiation in O(log N).
#
# F(n) = [[1,1],[1,0]]^n  [row 1, col 2]  (0-indexed Fibonacci)
#
# Uses Int128 for intermediate products to avoid overflow, since
# two Int64 values near 10^9 can overflow when multiplied.

const MOD = Int64(10^9 + 7)

# Represent a 2x2 matrix as a tuple of 4 Int64 values (row-major).
# This avoids heap allocation and leverages Julia's value-type tuples.
struct Mat2
    a::Int64
    b::Int64
    c::Int64
    d::Int64
end

"""
    mat_mul(A::Mat2, B::Mat2) -> Mat2

Multiply two 2x2 matrices mod MOD. Uses Int128 widening for
intermediate products to prevent overflow.
"""
function mat_mul(A::Mat2, B::Mat2)::Mat2
    # widen to Int128 for the multiply, then mod back to Int64
    mod128(x::Int128) = Int64(x % MOD)
    Mat2(
        mod128(Int128(A.a) * B.a + Int128(A.b) * B.c),
        mod128(Int128(A.a) * B.b + Int128(A.b) * B.d),
        mod128(Int128(A.c) * B.a + Int128(A.d) * B.c),
        mod128(Int128(A.c) * B.b + Int128(A.d) * B.d),
    )
end

"""
    mat_pow(M::Mat2, n) -> Mat2

Binary exponentiation of a 2x2 matrix, O(log n) multiplications.
"""
function mat_pow(M::Mat2, n::Union{Int64,Int128,UInt64})::Mat2
    result = Mat2(1, 0, 0, 1)  # identity
    base = M
    while n > 0
        if isodd(n)
            result = mat_mul(result, base)
        end
        base = mat_mul(base, base)
        n >>= 1
    end
    result
end

"""
    fibonacci(n) -> Int64

Return F(n) mod 10^9+7 where F(0)=0, F(1)=1.
"""
function fibonacci(n::Union{Int64,Int128,UInt64})::Int64
    n == 0 && return Int64(0)
    # [[1,1],[1,0]]^n  -> top-right element = F(n)
    M = Mat2(1, 1, 1, 0)
    R = mat_pow(M, n)
    R.b
end

function main()
    n = parse(Int128, strip(readline(stdin)))
    println(fibonacci(n))
end

main()
