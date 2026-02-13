# Longest Increasing Subsequence - O(N log N) with patience sorting
#
# Input:  line 1 = N, line 2 = N space-separated integers (can be negative)
# Output: length of the longest strictly increasing subsequence
#
# Algorithm: maintain a "tails" array where tails[i] is the smallest tail
# element for an increasing subsequence of length i+1. For each element,
# binary search for the lower_bound position and replace or extend.
#
# Time: O(N log N), Space: O(N)
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
.set BUFFER_SIZE, 65536
.set MAX_N, 200001

# BSS: input buffer and tails array
.zerofill __DATA,__bss,input_buf,65536,4
.zerofill __DATA,__bss,tails,1600008,4     # MAX_N * 8 bytes

# ============================================================================
# start - entry point
# ============================================================================
start:
    andq    $-16, %rsp

    # Read all input
    leaq    input_buf(%rip), %r15       # %r15 = input buffer base
    xorq    %r14, %r14                  # %r14 = total bytes read

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
    # Null-terminate
    movb    $0, (%r15, %r14)

    # Parse N
    movq    %r15, %rsi
    call    parse_int64                 # %rax = N
    movq    %rax, %r12                  # %r12 = N

    # If N == 0, output 0
    testq   %r12, %r12
    jnz     .Lhas_elements
    xorq    %rdi, %rdi
    call    write_uint64
    call    write_newline
    jmp     .Lexit

.Lhas_elements:
    # Read first element and initialize tails[0]
    call    parse_int64                 # first element
    leaq    tails(%rip), %r13           # %r13 = tails array base
    movq    %rax, (%r13)                # tails[0] = first element
    movq    $1, %rbx                    # %rbx = tails_len = 1

    # Process remaining N-1 elements
    movq    $1, %r14                    # i = 1
.Llis_loop:
    cmpq    %r12, %r14
    jge     .Llis_done

    call    parse_int64                 # %rax = arr[i]
    movq    %rax, %rdi                  # %rdi = current value

    # Compare with tails[tails_len - 1]
    movq    -8(%r13, %rbx, 8), %rax     # tails[tails_len - 1]
    cmpq    %rdi, %rax
    jge     .Lneed_bsearch              # if tails[last] >= val, binary search

    # Extend: tails[tails_len] = val, tails_len++
    movq    %rdi, (%r13, %rbx, 8)
    incq    %rbx
    jmp     .Llis_next

.Lneed_bsearch:
    # Binary search for lower_bound of val in tails[0..tails_len-1]
    # Find first index where tails[idx] >= val
    xorq    %rcx, %rcx                  # lo = 0
    movq    %rbx, %r8                   # hi = tails_len

.Lbs_loop:
    cmpq    %r8, %rcx
    jge     .Lbs_done
    movq    %rcx, %rax
    addq    %r8, %rax
    shrq    $1, %rax                    # mid = (lo + hi) / 2
    movq    (%r13, %rax, 8), %r9        # tails[mid]
    cmpq    %rdi, %r9
    jl      .Lbs_go_right               # tails[mid] < val -> go right
    # tails[mid] >= val -> hi = mid
    movq    %rax, %r8
    jmp     .Lbs_loop
.Lbs_go_right:
    leaq    1(%rax), %rcx               # lo = mid + 1
    jmp     .Lbs_loop

.Lbs_done:
    # rcx = lower_bound index, replace tails[rcx] with val
    movq    %rdi, (%r13, %rcx, 8)

.Llis_next:
    incq    %r14
    jmp     .Llis_loop

.Llis_done:
    # Output tails_len
    movq    %rbx, %rdi
    call    write_uint64
    call    write_newline

.Lexit:
    movq    $SYS_EXIT, %rax
    xorq    %rdi, %rdi
    syscall

# ============================================================================
# parse_int64: parse signed 64-bit integer from buffer at %rsi
# Returns value in %rax. Advances %rsi past the number.
# Handles optional leading '-' for negative numbers.
# ============================================================================
parse_int64:
    xorq    %rax, %rax
    xorq    %r11, %r11                  # sign flag: 0 = positive, 1 = negative
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
# write_newline: write '\n' to stdout
# ============================================================================
write_newline:
    movq    $SYS_WRITE, %rax
    movq    $STDOUT, %rdi
    leaq    newline(%rip), %rsi
    movq    $1, %rdx
    syscall
    ret
