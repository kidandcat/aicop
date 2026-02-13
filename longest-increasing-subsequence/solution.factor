USING: arrays io kernel locals math math.parser sequences splitting vectors ;
IN: script

! Longest Increasing Subsequence via patience sorting with binary search.
! Time complexity: O(N log N).

! Binary search for the leftmost index in sorted vector tails
! where tails[idx] >= val. Returns tails length if val exceeds all.
:: lower-bound ( tails val -- idx )
    0 :> lo!
    tails length :> hi!
    [ lo hi < ] [
        lo hi + 2 /i :> mid
        mid tails nth val < [
            mid 1 + lo!
        ] [
            mid hi!
        ] if
    ] while
    lo ;

! Patience sorting: maintain a vector of smallest tail elements
! for increasing subsequences of each length.
:: lis-length ( nums -- len )
    V{ } clone :> tails
    nums [| val |
        tails val lower-bound :> pos
        pos tails length = [
            val tails push
        ] [
            val pos tails set-nth
        ] if
    ] each
    tails length ;

:: main ( -- )
    readln drop
    readln " " split [ string>number ] map
    lis-length number>string print ;

MAIN: main
