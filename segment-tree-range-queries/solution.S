# NOTE: This is a simplified implementation. The segment tree logic is
# straightforward in assembly but requires careful stack management.
# This version handles arrays up to N=100000 elements.
#
# Segment Tree - Range Sum Queries with Point Updates
#
# Input:  first line = N Q (array size, number of queries)
#         second line = N space-separated integers (initial array values)
#         next Q lines = either "1 i v" (update a[i] = v) or "2 l r" (sum query)
#         Positions are 1-indexed in queries, converted to 0-indexed internally.
# Output: one line per query of type 2, containing the sum
#
# macOS x86-64 assembly, AT&T syntax, no libc.
# Compile: clang -target x86_64-apple-macos11 -nostdlib -static -e start -o solution_asm solution.S
# Run:     arch -x86_64 ./solution_asm

.section __DATA,__data
    newline: .byte 10

.section __TEXT,__text
.globl start

.set SYS_EXIT,  0x2000001
.set SYS_READ,  0x2000003
.set SYS_WRITE, 0x2000004
.set STDIN,  0
.set STDOUT, 1
.set BUFFER_SIZE, 131072
.set MAX_N, 100001
.set TREE_SIZE, 400004             # 4 * MAX_N

# BSS
.zerofill __DATA,__bss,input_buf,131072,4
.zerofill __DATA,__bss,arr,800008,4            # MAX_N * 8
.zerofill __DATA,__bss,tree,3200032,4          # TREE_SIZE * 8
.zerofill __DATA,__bss,out_buf,4194304,4       # 4MB output buffer

# Global variables stored in BSS
.zerofill __DATA,__bss,g_n,8,3                 # N
.zerofill __DATA,__bss,g_input_ptr,8,3         # current input pointer

# ============================================================================
# start
# ============================================================================
start:
    andq    $-16, %rsp

    # Read all input
    leaq    input_buf(%rip), %r15
    xorq    %r14, %r14

.Lread_loop:
    movq    $SYS_READ, %rax
    movq    $STDIN, %rdi
    leaq    (%r15, %r14), %rsi
    movq    $BUFFER_SIZE, %rdx
    subq    %r14, %rdx
    jle     .Lread_done
    syscall
    testq   %rax, %rax
    jle     .Lread_done
    addq    %rax, %r14
    jmp     .Lread_loop

.Lread_done:
    movb    $0, (%r15, %r14)

    # Parse N and Q
    movq    %r15, %rsi
    leaq    g_input_ptr(%rip), %rdi
    movq    %rsi, (%rdi)                # save input pointer

    call    parse_int64                 # N
    movq    %rax, %r12                  # %r12 = N
    leaq    g_n(%rip), %rdi
    movq    %rax, (%rdi)

    call    parse_int64                 # Q
    movq    %rax, %r13                  # %r13 = Q

    # Read array elements into arr[]
    leaq    arr(%rip), %rdi
    xorq    %rbx, %rbx
.Lread_arr:
    cmpq    %r12, %rbx
    jge     .Lread_arr_done
    call    parse_int64
    movq    %rax, (%rdi, %rbx, 8)
    incq    %rbx
    jmp     .Lread_arr

.Lread_arr_done:
    # Save input pointer
    leaq    g_input_ptr(%rip), %rdi
    movq    %rsi, (%rdi)

    # Build segment tree: build(1, 0, N-1)
    movq    $1, %rdi                    # v = 1
    xorq    %rsi, %rsi                  # tl = 0
    movq    %r12, %rdx
    decq    %rdx                        # tr = N-1
    call    seg_build

    # Process Q queries
    # Use r14 as output buffer pointer
    leaq    out_buf(%rip), %r14
    xorq    %rbx, %rbx                  # query counter

.Lquery_loop:
    cmpq    %r13, %rbx
    jge     .Lquery_done

    # Restore input pointer to %rsi
    leaq    g_input_ptr(%rip), %rdi
    movq    (%rdi), %rsi

    # Read query type
    call    parse_int64
    movq    %rax, %rcx                  # type (1 or 2)

    cmpq    $1, %rcx
    je      .Ldo_update

    # Type 2: range sum query
    call    parse_int64
    pushq   %rax                        # l (1-indexed)
    call    parse_int64
    movq    %rax, %r9                   # r (1-indexed)
    popq    %r8                         # l

    # Save input pointer
    leaq    g_input_ptr(%rip), %rdi
    movq    %rsi, (%rdi)

    # Convert to 0-indexed
    decq    %r8                         # l-1
    decq    %r9                         # r-1

    # query(1, 0, N-1, l-1, r-1)
    movq    $1, %rdi                    # v
    xorq    %rsi, %rsi                  # tl = 0
    movq    %r12, %rdx
    decq    %rdx                        # tr = N-1
    movq    %r8, %rcx                   # l
    movq    %r9, %r8                    # r
    call    seg_query                   # result in %rax

    # Write result to output buffer
    movq    %rax, %rdi
    call    write_int64_to_buf          # writes to (%r14), advances %r14

    # Write newline to buffer
    movb    $'\n', (%r14)
    incq    %r14

    jmp     .Lquery_next

.Ldo_update:
    # Type 1: point update
    call    parse_int64
    pushq   %rax                        # i (1-indexed)
    call    parse_int64
    movq    %rax, %r9                   # v (new value)
    popq    %r8                         # i

    # Save input pointer
    leaq    g_input_ptr(%rip), %rdi
    movq    %rsi, (%rdi)

    # Convert to 0-indexed
    decq    %r8                         # pos = i-1

    # update(1, 0, N-1, pos, val)
    movq    $1, %rdi                    # v (tree node)
    xorq    %rsi, %rsi                  # tl = 0
    movq    %r12, %rdx
    decq    %rdx                        # tr = N-1
    movq    %r8, %rcx                   # pos
    movq    %r9, %r8                    # val
    call    seg_update

.Lquery_next:
    incq    %rbx
    jmp     .Lquery_loop

.Lquery_done:
    # Flush output buffer
    leaq    out_buf(%rip), %rsi
    movq    %r14, %rdx
    subq    %rsi, %rdx                  # length
    testq   %rdx, %rdx
    jz      .Lexit

    movq    $SYS_WRITE, %rax
    movq    $STDOUT, %rdi
    syscall

.Lexit:
    movq    $SYS_EXIT, %rax
    xorq    %rdi, %rdi
    syscall

# ============================================================================
# seg_build(v, tl, tr): build segment tree node v covering [tl, tr]
# Args: %rdi=v, %rsi=tl, %rdx=tr
# ============================================================================
seg_build:
    pushq   %rbp
    movq    %rsp, %rbp
    pushq   %rbx
    pushq   %r12
    pushq   %r13
    pushq   %r14

    movq    %rdi, %r12                  # v
    movq    %rsi, %r13                  # tl
    movq    %rdx, %r14                  # tr

    cmpq    %r14, %r13
    jne     .Lbuild_recurse

    # Leaf: tree[v] = arr[tl]
    leaq    arr(%rip), %rax
    movq    (%rax, %r13, 8), %rax
    leaq    tree(%rip), %rcx
    movq    %rax, (%rcx, %r12, 8)
    jmp     .Lbuild_ret

.Lbuild_recurse:
    # tm = (tl + tr) / 2
    movq    %r13, %rbx
    addq    %r14, %rbx
    shrq    $1, %rbx                    # tm

    # build(2*v, tl, tm)
    movq    %r12, %rdi
    shlq    $1, %rdi                    # 2*v
    movq    %r13, %rsi                  # tl
    movq    %rbx, %rdx                  # tm
    call    seg_build

    # build(2*v+1, tm+1, tr)
    movq    %r12, %rdi
    shlq    $1, %rdi
    incq    %rdi                        # 2*v+1
    leaq    1(%rbx), %rsi               # tm+1
    movq    %r14, %rdx                  # tr
    call    seg_build

    # tree[v] = tree[2*v] + tree[2*v+1]
    leaq    tree(%rip), %rcx
    movq    %r12, %rax
    shlq    $1, %rax                    # 2*v
    movq    (%rcx, %rax, 8), %rdi       # tree[2*v]
    incq    %rax
    addq    (%rcx, %rax, 8), %rdi       # + tree[2*v+1]
    movq    %rdi, (%rcx, %r12, 8)       # tree[v] = sum

.Lbuild_ret:
    popq    %r14
    popq    %r13
    popq    %r12
    popq    %rbx
    popq    %rbp
    ret

# ============================================================================
# seg_update(v, tl, tr, pos, val): update position pos to val
# Args: %rdi=v, %rsi=tl, %rdx=tr, %rcx=pos, %r8=val
# ============================================================================
seg_update:
    pushq   %rbp
    movq    %rsp, %rbp
    pushq   %rbx
    pushq   %r12
    pushq   %r13
    pushq   %r14
    pushq   %r15

    movq    %rdi, %r12                  # v
    movq    %rsi, %r13                  # tl
    movq    %rdx, %r14                  # tr
    movq    %rcx, %r15                  # pos
    movq    %r8, %rbx                   # val

    cmpq    %r14, %r13
    jne     .Lupdate_recurse

    # Leaf: tree[v] = val
    leaq    tree(%rip), %rax
    movq    %rbx, (%rax, %r12, 8)
    jmp     .Lupdate_ret

.Lupdate_recurse:
    # tm = (tl + tr) / 2
    movq    %r13, %rax
    addq    %r14, %rax
    shrq    $1, %rax                    # tm
    pushq   %rax                        # save tm

    cmpq    %rax, %r15
    jg      .Lupdate_right

    # pos <= tm: update left child
    movq    %r12, %rdi
    shlq    $1, %rdi                    # 2*v
    movq    %r13, %rsi                  # tl
    movq    %rax, %rdx                  # tm
    movq    %r15, %rcx                  # pos
    movq    %rbx, %r8                   # val
    call    seg_update
    jmp     .Lupdate_merge

.Lupdate_right:
    # pos > tm: update right child
    movq    %r12, %rdi
    shlq    $1, %rdi
    incq    %rdi                        # 2*v+1
    popq    %rax                        # tm
    leaq    1(%rax), %rsi               # tm+1
    pushq   %rax                        # re-save tm
    movq    %r14, %rdx                  # tr
    movq    %r15, %rcx                  # pos
    movq    %rbx, %r8                   # val
    call    seg_update

.Lupdate_merge:
    popq    %rax                        # pop saved tm

    # tree[v] = tree[2*v] + tree[2*v+1]
    leaq    tree(%rip), %rcx
    movq    %r12, %rax
    shlq    $1, %rax
    movq    (%rcx, %rax, 8), %rdi
    incq    %rax
    addq    (%rcx, %rax, 8), %rdi
    movq    %rdi, (%rcx, %r12, 8)

.Lupdate_ret:
    popq    %r15
    popq    %r14
    popq    %r13
    popq    %r12
    popq    %rbx
    popq    %rbp
    ret

# ============================================================================
# seg_query(v, tl, tr, l, r): query sum of [l, r]
# Args: %rdi=v, %rsi=tl, %rdx=tr, %rcx=l, %r8=r
# Returns sum in %rax
# ============================================================================
seg_query:
    pushq   %rbp
    movq    %rsp, %rbp
    pushq   %rbx
    pushq   %r12
    pushq   %r13
    pushq   %r14
    pushq   %r15

    movq    %rdi, %r12                  # v
    movq    %rsi, %r13                  # tl
    movq    %rdx, %r14                  # tr
    movq    %rcx, %r15                  # l
    movq    %r8, %rbx                   # r

    # Check l > r: return 0
    cmpq    %rbx, %r15
    jg      .Lquery_zero

    # Check l == tl and r == tr: return tree[v]
    cmpq    %r13, %r15
    jne     .Lquery_recurse
    cmpq    %r14, %rbx
    jne     .Lquery_recurse

    # Exact match: return tree[v]
    leaq    tree(%rip), %rax
    movq    (%rax, %r12, 8), %rax
    jmp     .Lquery_ret

.Lquery_zero:
    xorq    %rax, %rax
    jmp     .Lquery_ret

.Lquery_recurse:
    # tm = (tl + tr) / 2
    movq    %r13, %rax
    addq    %r14, %rax
    shrq    $1, %rax                    # tm
    pushq   %rax                        # save tm

    # Query left: query(2*v, tl, tm, l, min(r, tm))
    movq    %r12, %rdi
    shlq    $1, %rdi                    # 2*v
    movq    %r13, %rsi                  # tl
    movq    %rax, %rdx                  # tm
    movq    %r15, %rcx                  # l
    # min(r, tm)
    movq    %rbx, %r8                   # r
    cmpq    %rax, %r8
    jle     .Lquery_left_ok
    movq    %rax, %r8                   # min(r, tm) = tm
.Lquery_left_ok:
    call    seg_query
    pushq   %rax                        # save left_sum

    # Query right: query(2*v+1, tm+1, tr, max(l, tm+1), r)
    movq    8(%rsp), %rax               # recover tm from stack (under left_sum)
    movq    %r12, %rdi
    shlq    $1, %rdi
    incq    %rdi                        # 2*v+1
    leaq    1(%rax), %rsi               # tm+1
    movq    %r14, %rdx                  # tr
    # max(l, tm+1)
    movq    %r15, %rcx                  # l
    cmpq    %rsi, %rcx
    jge     .Lquery_right_ok
    movq    %rsi, %rcx                  # max(l, tm+1) = tm+1
.Lquery_right_ok:
    movq    %rbx, %r8                   # r
    call    seg_query
    # rax = right_sum

    popq    %rcx                        # left_sum
    addq    %rcx, %rax                  # total = left + right
    popq    %rcx                        # pop saved tm (discard)
    jmp     .Lquery_ret

.Lquery_ret:
    popq    %r15
    popq    %r14
    popq    %r13
    popq    %r12
    popq    %rbx
    popq    %rbp
    ret

# ============================================================================
# parse_int64: parse signed 64-bit integer from buffer at %rsi
# Returns value in %rax. Advances %rsi.
# ============================================================================
parse_int64:
    xorq    %rax, %rax
    xorq    %r11, %r11
.Lpi_skip:
    movzbl  (%rsi), %ecx
    cmpb    $' ', %cl
    je      .Lpi_ws
    cmpb    $'\n', %cl
    je      .Lpi_ws
    cmpb    $'\r', %cl
    je      .Lpi_ws
    cmpb    $'\t', %cl
    je      .Lpi_ws
    jmp     .Lpi_check_sign
.Lpi_ws:
    incq    %rsi
    jmp     .Lpi_skip
.Lpi_check_sign:
    cmpb    $'-', %cl
    jne     .Lpi_digits
    movq    $1, %r11
    incq    %rsi
.Lpi_digits:
    movzbl  (%rsi), %ecx
    subb    $'0', %cl
    cmpb    $9, %cl
    ja      .Lpi_done
    imulq   $10, %rax, %rax
    movzbq  %cl, %rcx
    addq    %rcx, %rax
    incq    %rsi
    jmp     .Lpi_digits
.Lpi_done:
    testq   %r11, %r11
    jz      .Lpi_ret
    negq    %rax
.Lpi_ret:
    ret

# ============================================================================
# write_int64_to_buf: write signed 64-bit integer in %rdi to buffer at (%r14)
# Advances %r14. Handles negative numbers.
# ============================================================================
write_int64_to_buf:
    pushq   %rbp
    movq    %rsp, %rbp
    subq    $32, %rsp

    movq    %rdi, %rax

    # Handle negative
    testq   %rax, %rax
    jns     .Lwb_positive
    movb    $'-', (%r14)
    incq    %r14
    negq    %rax

.Lwb_positive:
    # Convert to decimal digits (reversed)
    leaq    -1(%rbp), %r9               # write position in local buffer
    xorq    %rcx, %rcx                  # digit count

    testq   %rax, %rax
    jnz     .Lwb_loop
    movb    $'0', (%r9)
    movq    $1, %rcx
    leaq    0(%r9), %rsi                # start
    jmp     .Lwb_copy

.Lwb_loop:
    testq   %rax, %rax
    jz      .Lwb_loop_done
    xorq    %rdx, %rdx
    movq    $10, %r8
    divq    %r8
    addb    $'0', %dl
    movb    %dl, (%r9)
    decq    %r9
    incq    %rcx
    jmp     .Lwb_loop

.Lwb_loop_done:
    leaq    1(%r9), %rsi                # first digit

.Lwb_copy:
    # Copy digits to output buffer at %r14
    xorq    %rdx, %rdx
.Lwb_copy_loop:
    cmpq    %rcx, %rdx
    jge     .Lwb_done
    movzbl  (%rsi, %rdx), %eax
    movb    %al, (%r14)
    incq    %r14
    incq    %rdx
    jmp     .Lwb_copy_loop

.Lwb_done:
    movq    %rbp, %rsp
    popq    %rbp
    ret

# ============================================================================
# write_newline
# ============================================================================
write_newline:
    movq    $SYS_WRITE, %rax
    movq    $STDOUT, %rdi
    leaq    newline(%rip), %rsi
    movq    $1, %rdx
    syscall
    ret
