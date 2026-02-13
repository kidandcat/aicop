# KMP String Matching
#
# Input:  line 1 = text, line 2 = pattern
# Output: first line = count of matches
#         second line = space-separated 0-based positions (empty if no matches)
#
# Algorithm: Build LPS (Longest Proper Prefix which is also Suffix) array,
# then scan text using KMP automaton to find all occurrences including
# overlapping ones.
#
# Time: O(N + M), Space: O(M) for LPS array
#
# macOS x86-64 assembly, AT&T syntax, no libc.
# Compile: clang -target x86_64-apple-macos11 -nostdlib -static -e start -o solution_asm solution.S
# Run:     arch -x86_64 ./solution_asm

.section __DATA,__data
    newline: .byte 10
    space:   .byte 32

.section __TEXT,__text
.globl start

.set SYS_EXIT,  0x2000001
.set SYS_READ,  0x2000003
.set SYS_WRITE, 0x2000004
.set STDIN,  0
.set STDOUT, 1
.set BUFFER_SIZE, 131072
.set MAX_TEXT, 100001
.set MAX_PAT,  100001
.set MAX_MATCHES, 100001

# BSS
.zerofill __DATA,__bss,input_buf,131072,4
.zerofill __DATA,__bss,text_buf,100001,4
.zerofill __DATA,__bss,pat_buf,100001,4
.zerofill __DATA,__bss,lps_arr,800008,4         # MAX_PAT * 8
.zerofill __DATA,__bss,matches,800008,4          # MAX_MATCHES * 8
.zerofill __DATA,__bss,out_buf,2097152,4         # 2MB output buffer

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

    # Parse text (first line) into text_buf
    movq    %r15, %rsi
    leaq    text_buf(%rip), %rdi
    call    read_line                   # returns length in %rax, advances %rsi
    movq    %rax, %r12                  # %r12 = text_len

    # Parse pattern (second line) into pat_buf
    leaq    pat_buf(%rip), %rdi
    call    read_line
    movq    %rax, %r13                  # %r13 = pat_len

    # Build LPS array for pattern
    leaq    pat_buf(%rip), %rdi
    leaq    lps_arr(%rip), %rsi
    movq    %r13, %rdx
    call    build_lps

    # KMP search
    leaq    text_buf(%rip), %rdi        # text
    movq    %r12, %rsi                  # text_len
    leaq    pat_buf(%rip), %rdx         # pattern
    movq    %r13, %rcx                  # pat_len
    leaq    lps_arr(%rip), %r8          # lps
    leaq    matches(%rip), %r9          # matches output array
    call    kmp_search                  # returns match_count in %rax

    movq    %rax, %rbx                  # %rbx = match_count

    # Output: count on line 1
    movq    %rbx, %rdi
    call    write_uint64
    call    write_newline

    # Output: positions on line 2 (space-separated, empty line if no matches)
    testq   %rbx, %rbx
    jz      .Lempty_line

    leaq    matches(%rip), %r13
    xorq    %r14, %r14                  # i = 0

.Lprint_matches:
    cmpq    %rbx, %r14
    jge     .Lprint_matches_done

    # Print space before all but first
    testq   %r14, %r14
    jz      .Lno_space
    call    write_space
.Lno_space:
    movq    (%r13, %r14, 8), %rdi
    call    write_uint64
    incq    %r14
    jmp     .Lprint_matches

.Lprint_matches_done:

.Lempty_line:
    call    write_newline

.Lexit:
    movq    $SYS_EXIT, %rax
    xorq    %rdi, %rdi
    syscall

# ============================================================================
# read_line: copy line from (%rsi) to (%rdi), null-terminate
# Returns length in %rax, advances %rsi past the newline
# ============================================================================
read_line:
    xorq    %rax, %rax                  # length = 0
.Lrl_loop:
    movzbl  (%rsi), %ecx
    testb   %cl, %cl
    jz      .Lrl_done
    cmpb    $'\n', %cl
    je      .Lrl_newline
    cmpb    $'\r', %cl
    je      .Lrl_cr
    movb    %cl, (%rdi, %rax)
    incq    %rax
    incq    %rsi
    jmp     .Lrl_loop
.Lrl_cr:
    incq    %rsi                        # skip \r
    jmp     .Lrl_loop
.Lrl_newline:
    incq    %rsi                        # skip \n
.Lrl_done:
    movb    $0, (%rdi, %rax)            # null-terminate
    ret

# ============================================================================
# build_lps: build the LPS (failure function) array for KMP
# Input: %rdi = pattern, %rsi = lps array, %rdx = pat_len
# ============================================================================
build_lps:
    pushq   %rbx
    pushq   %r12
    pushq   %r13
    pushq   %r14

    movq    %rdi, %r12                  # pattern
    movq    %rsi, %r13                  # lps array
    movq    %rdx, %r14                  # pat_len

    # lps[0] = 0
    movq    $0, (%r13)

    cmpq    $1, %r14
    jle     .Lblps_done

    xorq    %rbx, %rbx                  # len = 0 (length of previous longest prefix suffix)
    movq    $1, %rcx                    # i = 1

.Lblps_loop:
    cmpq    %r14, %rcx
    jge     .Lblps_done

    # Compare pattern[i] with pattern[len]
    movzbl  (%r12, %rcx), %eax
    movzbl  (%r12, %rbx), %edx
    cmpb    %dl, %al
    jne     .Lblps_mismatch

    # Match: lps[i] = len + 1, i++, len++
    incq    %rbx
    movq    %rbx, (%r13, %rcx, 8)
    incq    %rcx
    jmp     .Lblps_loop

.Lblps_mismatch:
    testq   %rbx, %rbx
    jz      .Lblps_zero

    # len = lps[len - 1]
    movq    -8(%r13, %rbx, 8), %rbx
    jmp     .Lblps_loop

.Lblps_zero:
    # lps[i] = 0, i++
    movq    $0, (%r13, %rcx, 8)
    incq    %rcx
    jmp     .Lblps_loop

.Lblps_done:
    popq    %r14
    popq    %r13
    popq    %r12
    popq    %rbx
    ret

# ============================================================================
# kmp_search: find all occurrences of pattern in text
# Input: %rdi = text, %rsi = text_len, %rdx = pattern, %rcx = pat_len,
#        %r8 = lps, %r9 = matches output array
# Returns: match count in %rax
# ============================================================================
kmp_search:
    pushq   %rbx
    pushq   %r12
    pushq   %r13
    pushq   %r14
    pushq   %r15
    pushq   %rbp

    movq    %rdi, %r12                  # text
    movq    %rsi, %r13                  # text_len
    movq    %rdx, %r14                  # pattern
    movq    %rcx, %r15                  # pat_len
    movq    %r8, %rbp                   # lps
    # %r9 = matches array (already set)

    xorq    %rax, %rax                  # match_count = 0
    xorq    %rbx, %rbx                  # j = 0 (pattern index)
    xorq    %rcx, %rcx                  # i = 0 (text index)

    # If pat_len == 0, return 0 matches
    testq   %r15, %r15
    jz      .Lkmp_done

.Lkmp_loop:
    cmpq    %r13, %rcx
    jge     .Lkmp_done

    # Compare text[i] with pattern[j]
    movzbl  (%r12, %rcx), %edx
    movzbl  (%r14, %rbx), %edi
    cmpb    %dil, %dl
    jne     .Lkmp_mismatch

    # Match
    incq    %rcx
    incq    %rbx

    # Check if full pattern matched
    cmpq    %r15, %rbx
    jne     .Lkmp_loop

    # Found a match at position i - pat_len
    movq    %rcx, %rdi
    subq    %r15, %rdi
    movq    %rdi, (%r9, %rax, 8)        # matches[match_count] = i - pat_len
    incq    %rax

    # Continue searching: j = lps[j-1]
    movq    -8(%rbp, %rbx, 8), %rbx
    jmp     .Lkmp_loop

.Lkmp_mismatch:
    testq   %rbx, %rbx
    jz      .Lkmp_inc_i

    # j = lps[j-1]
    movq    -8(%rbp, %rbx, 8), %rbx
    jmp     .Lkmp_loop

.Lkmp_inc_i:
    incq    %rcx
    jmp     .Lkmp_loop

.Lkmp_done:
    popq    %rbp
    popq    %r15
    popq    %r14
    popq    %r13
    popq    %r12
    popq    %rbx
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
# write_newline / write_space
# ============================================================================
write_newline:
    movq    $SYS_WRITE, %rax
    movq    $STDOUT, %rdi
    leaq    newline(%rip), %rsi
    movq    $1, %rdx
    syscall
    ret

write_space:
    movq    $SYS_WRITE, %rax
    movq    $STDOUT, %rdi
    leaq    space(%rip), %rsi
    movq    $1, %rdx
    syscall
    ret
