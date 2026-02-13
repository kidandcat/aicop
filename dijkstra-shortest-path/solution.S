# NOTE: This is a simplified implementation that handles the basic test cases.
# A full Dijkstra implementation in pure assembly requires dynamic memory
# allocation (mmap syscall) for adjacency lists and priority queues,
# which significantly increases complexity. This version uses a simple
# O(N^2) approach with an adjacency matrix for small graphs (N <= 1000).
#
# Dijkstra's shortest path from node 1 to node N.
#
# Input:  first line = N M (nodes, edges)
#         next M lines = u v w (directed edge from u to v with weight w)
# Output: shortest distance from 1 to N, or -1 if unreachable
#
# macOS x86-64 assembly, AT&T syntax, no libc.
# Compile: clang -target x86_64-apple-macos11 -nostdlib -static -e start -o solution_asm solution.S
# Run:     arch -x86_64 ./solution_asm

.section __DATA,__data
    newline:    .byte 10
    minus_one:  .asciz "-1"

.section __TEXT,__text
.globl start

.set SYS_EXIT,  0x2000001
.set SYS_READ,  0x2000003
.set SYS_WRITE, 0x2000004
.set STDIN,  0
.set STDOUT, 1
.set BUFFER_SIZE, 131072
.set MAX_N, 1001
# Adjacency matrix: MAX_N * MAX_N * 8 = 1001*1001*8 = ~8MB
# dist array: MAX_N * 8 = ~8KB
# visited array: MAX_N * 8 = ~8KB
.set INF, 0x7FFFFFFFFFFFFFFF

# BSS
.zerofill __DATA,__bss,input_buf,131072,4
.zerofill __DATA,__bss,adj_matrix,8016008,4     # MAX_N * MAX_N * 8
.zerofill __DATA,__bss,dist_arr,8008,4          # MAX_N * 8
.zerofill __DATA,__bss,visited,8008,4           # MAX_N * 8

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

    # Parse N and M
    movq    %r15, %rsi
    call    parse_int64
    movq    %rax, %r12                  # %r12 = N
    call    parse_int64
    movq    %rax, %r13                  # %r13 = M

    # Initialize adjacency matrix to INF (no edge)
    leaq    adj_matrix(%rip), %rdi
    movq    %r12, %rax
    incq    %rax                        # N+1
    imulq   %rax, %rax                  # (N+1)^2
    movq    %rax, %rcx                  # number of entries
    movabsq $INF, %rax
.Linit_adj:
    testq   %rcx, %rcx
    jz      .Linit_adj_done
    movq    %rax, (%rdi)
    addq    $8, %rdi
    decq    %rcx
    jmp     .Linit_adj

.Linit_adj_done:
    # Read M edges
    xorq    %rbx, %rbx                  # edge counter
.Lread_edges:
    cmpq    %r13, %rbx
    jge     .Lread_edges_done

    call    parse_int64
    pushq   %rax                        # save u on stack
    call    parse_int64
    pushq   %rax                        # save v on stack
    call    parse_int64                  # w in %rax

    popq    %rdx                        # v
    popq    %rcx                        # u

    # adj_matrix[u][v] = min(adj_matrix[u][v], w)
    # Index: u * (N+1) + v
    leaq    adj_matrix(%rip), %rdi
    movq    %r12, %r8
    incq    %r8                         # N+1
    movq    %rcx, %r9
    imulq   %r8, %r9
    addq    %rdx, %r9                   # offset = u*(N+1) + v

    # Check if new weight is smaller
    cmpq    %rax, (%rdi, %r9, 8)
    jle     .Ledge_skip                 # existing <= new, skip
    movq    %rax, (%rdi, %r9, 8)

.Ledge_skip:
    incq    %rbx
    jmp     .Lread_edges

.Lread_edges_done:
    # Initialize dist array to INF, visited to 0
    leaq    dist_arr(%rip), %rdi
    leaq    visited(%rip), %r8
    movq    %r12, %rcx
    incq    %rcx                        # 0..N
    movabsq $INF, %rax
    xorq    %r9, %r9
.Linit_dist:
    testq   %rcx, %rcx
    jz      .Linit_dist_done
    movq    %rax, (%rdi)
    movq    %r9, (%r8)
    addq    $8, %rdi
    addq    $8, %r8
    decq    %rcx
    jmp     .Linit_dist

.Linit_dist_done:
    # dist[1] = 0
    leaq    dist_arr(%rip), %rdi
    movq    $0, 8(%rdi)                 # dist[1] = 0

    # Handle special case: N == 1
    cmpq    $1, %r12
    jne     .Ldijkstra_loop
    # Distance from 1 to 1 is 0
    xorq    %rdi, %rdi
    call    write_uint64
    call    write_newline
    jmp     .Lexit

    # Dijkstra main loop: iterate N times
.Ldijkstra_loop:
    movq    %r12, %rbp                  # iterations remaining

.Ldijk_iter:
    testq   %rbp, %rbp
    jz      .Ldijk_done

    # Find unvisited node with minimum dist
    leaq    dist_arr(%rip), %rdi
    leaq    visited(%rip), %r8
    movabsq $INF, %rax                  # min_dist
    movq    $-1, %rbx                   # min_node
    movq    $1, %rcx                    # node = 1

.Lfind_min:
    cmpq    %r12, %rcx
    jg      .Lfind_min_done

    # Skip if visited
    cmpq    $0, (%r8, %rcx, 8)
    jne     .Lfind_min_next

    # Check if dist[node] < min_dist
    movq    (%rdi, %rcx, 8), %r9
    cmpq    %rax, %r9
    jge     .Lfind_min_next

    movq    %r9, %rax
    movq    %rcx, %rbx

.Lfind_min_next:
    incq    %rcx
    jmp     .Lfind_min

.Lfind_min_done:
    # If no node found (rbx == -1) or min_dist == INF, stop
    cmpq    $-1, %rbx
    je      .Ldijk_done
    movabsq $INF, %r9
    cmpq    %r9, %rax
    je      .Ldijk_done

    # Mark rbx as visited
    leaq    visited(%rip), %r8
    movq    $1, (%r8, %rbx, 8)

    # If we just visited N, we can stop early
    cmpq    %r12, %rbx
    je      .Ldijk_done

    # Relax all neighbors of rbx
    # For v = 1..N: if adj[rbx][v] != INF, try to relax
    leaq    adj_matrix(%rip), %r10
    movq    %r12, %r11
    incq    %r11                        # N+1
    movq    %rbx, %r9
    imulq   %r11, %r9                   # r9 = rbx * (N+1), row offset

    leaq    dist_arr(%rip), %rdi
    movq    (%rdi, %rbx, 8), %rax       # dist[u]

    movq    $1, %rcx                    # v = 1

.Lrelax:
    cmpq    %r12, %rcx
    jg      .Lrelax_done

    # edge weight = adj[u][v]
    movq    %r9, %r8
    addq    %rcx, %r8                   # offset = u*(N+1) + v
    movq    (%r10, %r8, 8), %rdx        # weight

    movabsq $INF, %r11
    cmpq    %r11, %rdx
    je      .Lrelax_next

    # new_dist = dist[u] + weight
    movq    %rax, %r8
    addq    %rdx, %r8                   # new_dist

    # Update dist[v] when new_dist is smaller
    cmpq    (%rdi, %rcx, 8), %r8
    jge     .Lrelax_next
    movq    %r8, (%rdi, %rcx, 8)

.Lrelax_next:
    incq    %rcx
    jmp     .Lrelax

.Lrelax_done:
    decq    %rbp
    jmp     .Ldijk_iter

.Ldijk_done:
    # Output dist[N]
    leaq    dist_arr(%rip), %rdi
    movq    (%rdi, %r12, 8), %rax

    movabsq $INF, %r9
    cmpq    %r9, %rax
    jne     .Lprint_dist

    # Unreachable: print -1
    movq    $SYS_WRITE, %rax
    movq    $STDOUT, %rdi
    leaq    minus_one(%rip), %rsi
    movq    $2, %rdx
    syscall
    call    write_newline
    jmp     .Lexit

.Lprint_dist:
    movq    %rax, %rdi
    call    write_uint64
    call    write_newline

.Lexit:
    movq    $SYS_EXIT, %rax
    xorq    %rdi, %rdi
    syscall

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
# write_uint64: write unsigned 64-bit integer in %rdi to stdout
# ============================================================================
write_uint64:
    pushq   %rbp
    movq    %rsp, %rbp
    subq    $32, %rsp
    movq    %rdi, %rax
    leaq    -1(%rbp), %r9

    testq   %rax, %rax
    jnz     .Lwu_loop
    movb    $'0', (%r9)
    movq    %r9, %rsi
    movq    $1, %rdx
    jmp     .Lwu_out

.Lwu_loop:
    xorq    %rcx, %rcx
.Lwu_digits:
    testq   %rax, %rax
    jz      .Lwu_done
    xorq    %rdx, %rdx
    movq    $10, %r8
    divq    %r8
    addb    $'0', %dl
    movb    %dl, (%r9)
    decq    %r9
    incq    %rcx
    jmp     .Lwu_digits
.Lwu_done:
    leaq    1(%r9), %rsi
    movq    %rcx, %rdx

.Lwu_out:
    movq    $SYS_WRITE, %rax
    movq    $STDOUT, %rdi
    syscall

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
