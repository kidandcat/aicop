USING: arrays io kernel locals math math.parser sequences splitting vectors ;
IN: script

! Array-based segment tree for range sum queries with point updates.
! Tree is stored in a 1-indexed array of size 4*N.
!
! Input format:
!   Line 1: "N Q" (array size, number of operations)
!   Line 2: N space-separated integers (initial array)
!   Next Q lines, each one of:
!     "1 i val" -- set position i to val (1-indexed)
!     "2 l r"   -- print sum of A[l..r] (1-indexed, inclusive)

! Build the segment tree from the initial array.
:: seg-build ( arr tree node lo hi -- )
    lo hi = [
        lo 1 - arr nth node tree set-nth
    ] [
        lo hi + 2 /i :> mid
        node 2 * :> left
        node 2 * 1 + :> right
        arr tree left  lo     mid   seg-build
        arr tree right mid 1 + hi   seg-build
        left tree nth right tree nth + node tree set-nth
    ] if ;

! Point update: set position idx to val.
:: seg-update ( tree node lo hi idx val -- )
    lo hi = [
        val node tree set-nth
    ] [
        lo hi + 2 /i :> mid
        node 2 * :> left
        node 2 * 1 + :> right
        idx mid <= [
            tree left  lo     mid  idx val seg-update
        ] [
            tree right mid 1 + hi  idx val seg-update
        ] if
        left tree nth right tree nth + node tree set-nth
    ] if ;

! Range query: sum of elements in [ql, qr].
:: seg-query ( tree node lo hi ql qr -- sum )
    lo qr > hi ql < or [
        0
    ] [
        ql lo <= qr hi >= and [
            node tree nth
        ] [
            lo hi + 2 /i :> mid
            node 2 * :> left
            node 2 * 1 + :> right
            tree left  lo     mid  ql qr seg-query
            tree right mid 1 + hi  ql qr seg-query +
        ] if
    ] if ;

:: main ( -- )
    readln " " split [ string>number ] map :> nq
    0 nq nth :> n
    1 nq nth :> q

    readln " " split [ string>number ] map :> arr

    n 4 * 1 + 0 <array> :> tree
    arr tree 1 1 n seg-build

    q [
        readln " " split [ string>number ] map :> op
        0 op nth 1 = [
            tree 1 1 n  1 op nth  2 op nth  seg-update
        ] [
            tree 1 1 n  1 op nth  2 op nth  seg-query
            number>string print
        ] if
    ] times ;

MAIN: main
