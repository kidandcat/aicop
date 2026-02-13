USING: io kernel math math.parser sequences arrays locals ;
IN: script

! Compute N-th Fibonacci number mod 10^9+7 using matrix exponentiation.
! F(0)=0, F(1)=1, F(2)=1, ...
! Uses the identity: [[1,1],[1,0]]^n = [[F(n+1),F(n)],[F(n),F(n-1)]]

: MOD ( -- n ) 1000000007 ;

:: mat-mul-mod ( a b -- c )
    a first first  b first first  *  a first second  b second first  * + MOD mod :> c00
    a first first  b first second *  a first second  b second second * + MOD mod :> c01
    a second first b first first  *  a second second b second first  * + MOD mod :> c10
    a second first b first second *  a second second b second second * + MOD mod :> c11
    { { c00 c01 } { c10 c11 } } ;

:: mat-pow ( m n -- r )
    { { 1 0 } { 0 1 } } :> result!
    m :> base!
    n :> exp!
    [ exp 0 > ] [
        exp 1 bitand 1 = [
            result base mat-mul-mod result!
        ] when
        base base mat-mul-mod base!
        exp -1 shift exp!
    ] while
    result ;

: fib ( n -- f )
    dup 0 = [ drop 0 ] [
        { { 1 1 } { 1 0 } } swap mat-pow
        first second
    ] if ;

: main ( -- )
    readln string>number fib number>string print ;

MAIN: main
