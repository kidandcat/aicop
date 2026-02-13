USING: arrays io kernel locals math math.parser sequences splitting vectors heaps ;
IN: script

! Dijkstra's shortest path from node 1 to node N.
! Input: first line "N M", then M lines "u v w" (1-indexed, directed graph).
! Output: shortest distance from 1 to N, or -1 if unreachable.
! Uses a min-heap priority queue for O((V+E) log V) complexity.

:: main ( -- )
    readln " " split [ string>number ] map :> nm
    0 nm nth :> n
    1 nm nth :> m

    ! Build adjacency list (0-indexed internally)
    n [ V{ } clone ] replicate :> adj

    m [
        readln " " split [ string>number ] map :> edge
        0 edge nth 1 - :> u
        1 edge nth 1 - :> v
        2 edge nth :> w
        { v w } u adj nth push
    ] times

    ! Distance array: -1 means unvisited
    n -1 <array> :> dist
    0 0 dist set-nth

    ! Priority queue: value=node, key=distance
    <min-heap> :> pq
    0 0 pq heap-push

    [ pq heap-empty? not ] [
        pq heap-pop :> d :> u
        d u dist nth = [
            u adj nth [| edge |
                0 edge nth :> v
                1 edge nth :> w
                d w + :> nd
                v dist nth -1 = [ t ] [ nd v dist nth < ] if [
                    nd v dist set-nth
                    v nd pq heap-push
                ] when
            ] each
        ] when
    ] while

    n 1 - dist nth number>string print ;

MAIN: main
