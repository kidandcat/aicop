# Compute N-th Fibonacci number mod 10^9+7 using matrix exponentiation.
# F(0) = 0, F(1) = 1, F(N) = F(N-1) + F(N-2)
#
# Uses the identity:
#   |F(n+1)  F(n)  |   |1 1|^n
#   |F(n)    F(n-1)| = |1 0|
#
# Time: O(log N), Space: O(1)
#
# macOS x86-64 assembly, AT&T syntax, no libc.
# Compile: clang -target x86_64-apple-macos11 -nostdlib -static -e start -o solution_asm solution.S
# Run:     arch -x86_64 ./solution_asm

.section __DATA,__data
    newline: .byte 10

.section __TEXT,__text
.globl start

# ============================================================================
# Constants
# ============================================================================
.set MOD, 1000000007
.set SYS_EXIT,  0x2000001
.set SYS_READ,  0x2000003
.set SYS_WRITE, 0x2000004
.set STDIN,  0
.set STDOUT, 1
.set BUFFER_SIZE, 65536

# ============================================================================
# BSS: buffers
# ============================================================================
.zerofill __DATA,__bss,input_buf,65536,4

# ============================================================================
# start - entry point
# ============================================================================
start:
    andq    $-16, %rsp

    # Read input from stdin
    movq    $SYS_READ, %rax
    movq    $STDIN, %rdi
    leaq    input_buf(%rip), %rsi
    movq    $BUFFER_SIZE, %rdx
    syscall

    # Parse N from input
    leaq    input_buf(%rip), %rsi
    call    parse_uint64            # %rax = N
    movq    %rax, %rbx              # %rbx = N

    # Handle N == 0
    testq   %rbx, %rbx
    jnz     .Lnot_zero
    xorq    %rdi, %rdi
    call    write_uint64
    call    write_newline
    jmp     .Lexit

.Lnot_zero:
    # Allocate stack for two 2x2 matrices (4 qwords each = 32 bytes each)
    # [rsp+0..31]  = result (identity)
    # [rsp+32..63] = base
    subq    $64, %rsp

    # Result = identity [[1,0],[0,1]]
    movq    $1,  0(%rsp)
    movq    $0,  8(%rsp)
    movq    $0, 16(%rsp)
    movq    $1, 24(%rsp)

    # Base = [[1,1],[1,0]]
    movq    $1, 32(%rsp)
    movq    $1, 40(%rsp)
    movq    $1, 48(%rsp)
    movq    $0, 56(%rsp)

    movq    %rbx, %rcx              # %rcx = exponent

    # Binary exponentiation
.Lexp_loop:
    testq   %rcx, %rcx
    jz      .Lexp_done

    testq   $1, %rcx
    jz      .Lskip_mul

    # result = result * base
    # Temp matrix on stack: push 32 bytes
    # After push: temp=[rsp], result=[rsp+32], base=[rsp+64]
    subq    $32, %rsp
    movq    $MOD, %r8

    # temp[0][0] = (r00*b00 + r01*b10) % MOD
    movq    32(%rsp), %rax
    imulq   64(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, %r9
    movq    40(%rsp), %rax
    imulq   80(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    addq    %rdx, %r9
    movq    %r9, %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, 0(%rsp)

    # temp[0][1] = (r00*b01 + r01*b11) % MOD
    movq    32(%rsp), %rax
    imulq   72(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, %r9
    movq    40(%rsp), %rax
    imulq   88(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    addq    %rdx, %r9
    movq    %r9, %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, 8(%rsp)

    # temp[1][0] = (r10*b00 + r11*b10) % MOD
    movq    48(%rsp), %rax
    imulq   64(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, %r9
    movq    56(%rsp), %rax
    imulq   80(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    addq    %rdx, %r9
    movq    %r9, %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, 16(%rsp)

    # temp[1][1] = (r10*b01 + r11*b11) % MOD
    movq    48(%rsp), %rax
    imulq   72(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, %r9
    movq    56(%rsp), %rax
    imulq   88(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    addq    %rdx, %r9
    movq    %r9, %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, 24(%rsp)

    # Copy temp -> result
    movq    0(%rsp),  %rax
    movq    %rax, 32(%rsp)
    movq    8(%rsp),  %rax
    movq    %rax, 40(%rsp)
    movq    16(%rsp), %rax
    movq    %rax, 48(%rsp)
    movq    24(%rsp), %rax
    movq    %rax, 56(%rsp)

    addq    $32, %rsp

.Lskip_mul:
    # base = base * base
    subq    $32, %rsp
    movq    $MOD, %r8

    # temp[0][0] = (b00^2 + b01*b10) % MOD
    movq    64(%rsp), %rax
    imulq   %rax, %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, %r9
    movq    72(%rsp), %rax
    imulq   80(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    addq    %rdx, %r9
    movq    %r9, %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, 0(%rsp)

    # temp[0][1] = (b00*b01 + b01*b11) % MOD
    movq    64(%rsp), %rax
    imulq   72(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, %r9
    movq    72(%rsp), %rax
    imulq   88(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    addq    %rdx, %r9
    movq    %r9, %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, 8(%rsp)

    # temp[1][0] = (b10*b00 + b11*b10) % MOD
    movq    80(%rsp), %rax
    imulq   64(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, %r9
    movq    88(%rsp), %rax
    imulq   80(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    addq    %rdx, %r9
    movq    %r9, %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, 16(%rsp)

    # temp[1][1] = (b10*b01 + b11^2) % MOD
    movq    80(%rsp), %rax
    imulq   72(%rsp), %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, %r9
    movq    88(%rsp), %rax
    imulq   %rax, %rax
    xorq    %rdx, %rdx
    divq    %r8
    addq    %rdx, %r9
    movq    %r9, %rax
    xorq    %rdx, %rdx
    divq    %r8
    movq    %rdx, 24(%rsp)

    # Copy temp -> base
    movq    0(%rsp),  %rax
    movq    %rax, 64(%rsp)
    movq    8(%rsp),  %rax
    movq    %rax, 72(%rsp)
    movq    16(%rsp), %rax
    movq    %rax, 80(%rsp)
    movq    24(%rsp), %rax
    movq    %rax, 88(%rsp)

    addq    $32, %rsp

    shrq    $1, %rcx
    jmp     .Lexp_loop

.Lexp_done:
    # F(N) = result[0][1]
    movq    8(%rsp), %rdi
    addq    $64, %rsp
    call    write_uint64
    call    write_newline

.Lexit:
    movq    $SYS_EXIT, %rax
    xorq    %rdi, %rdi
    syscall

# ============================================================================
# parse_uint64: parse unsigned 64-bit integer from buffer at %rsi
# Returns value in %rax. Advances %rsi past the number.
# ============================================================================
parse_uint64:
    xorq    %rax, %rax
.Lpu_skip:
    movzbl  (%rsi), %ecx
    cmpb    $' ', %cl
    je      .Lpu_ws
    cmpb    $'\n', %cl
    je      .Lpu_ws
    cmpb    $'\r', %cl
    je      .Lpu_ws
    cmpb    $'\t', %cl
    je      .Lpu_ws
    jmp     .Lpu_digits
.Lpu_ws:
    incq    %rsi
    jmp     .Lpu_skip
.Lpu_digits:
    movzbl  (%rsi), %ecx
    subb    $'0', %cl
    cmpb    $9, %cl
    ja      .Lpu_done
    imulq   $10, %rax, %rax
    movzbq  %cl, %rcx
    addq    %rcx, %rax
    incq    %rsi
    jmp     .Lpu_digits
.Lpu_done:
    ret

# ============================================================================
# write_uint64: write unsigned 64-bit integer in %rdi to stdout
# ============================================================================
write_uint64:
    pushq   %rbp
    movq    %rsp, %rbp
    subq    $32, %rsp
    movq    %rdi, %rax
    leaq    -1(%rbp), %r9           # write position (end of local buffer)

    testq   %rax, %rax
    jnz     .Lwu_loop
    # Zero case
    movb    $'0', (%r9)
    movq    %r9, %rsi
    movq    $1, %rdx
    jmp     .Lwu_out

.Lwu_loop:
    xorq    %rcx, %rcx              # digit count
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
    leaq    1(%r9), %rsi            # first digit
    movq    %rcx, %rdx              # length

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
