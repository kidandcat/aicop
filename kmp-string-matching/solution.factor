USING: arrays io kernel locals math math.parser sequences splitting vectors ;
IN: script

! KMP (Knuth-Morris-Pratt) string matching algorithm.
! Builds LPS array (longest proper prefix which is also suffix),
! then searches text for all occurrences of pattern.

! Build the LPS array for a given pattern string.
:: build-lps ( pattern -- lps )
    pattern length :> plen
    plen 0 <array> :> lps
    0 :> len!
    1 :> i!
    [ i plen < ] [
        i pattern nth len pattern nth = [
            len 1 + len!
            len i lps set-nth
            i 1 + i!
        ] [
            len 0 > [
                len 1 - lps nth len!
            ] [
                0 i lps set-nth
                i 1 + i!
            ] if
        ] if
    ] while
    lps ;

! Search for all occurrences of pattern in text.
! Returns a vector of 0-based starting positions.
:: kmp-search ( text pattern -- positions )
    V{ } clone :> results
    pattern build-lps :> lps
    text length :> tlen
    pattern length :> plen
    0 :> i!
    0 :> j!
    [ i tlen < ] [
        i text nth j pattern nth = [
            i 1 + i!
            j 1 + j!
        ] [
            j 0 > [
                j 1 - lps nth j!
            ] [
                i 1 + i!
            ] if
        ] if
        j plen = [
            i plen - results push
            j 1 - lps nth j!
        ] when
    ] while
    results ;

:: main ( -- )
    readln :> text
    readln :> pattern
    text pattern kmp-search :> matches
    matches length number>string print
    matches [ number>string ] map " " join print ;

MAIN: main
