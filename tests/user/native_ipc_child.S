.intel_syntax noprefix
.section .text
.global _start
_start:
    mov r12, rsp
    sub r12, 16
    mov eax, 4
    int 0x80
    cmp rax, 1
    jne failed
.accept:
    mov edi, 1
    mov eax, 5
    int 0x80
    cmp rax, -1
    je .accept
    cmp rax, 1
    jl failed
    mov r13, rax
    mov rdi, r13
    mov eax, 10
    int 0x80
    cmp rax, 1
    jl failed

    mov rdi, r13
    xor esi, esi
    mov edx, 2
    mov eax, 7
    int 0x80
    cmp rax, -14
    jne failed
    mov rdi, r13
    lea rsi, [r12 + 15]
    mov edx, 2
    mov eax, 7
    int 0x80
    cmp rax, -14
    jne failed
.receive:
    mov rdi, r13
    mov eax, 8
    int 0x80
    cmp rax, -11
    je .receive
    test rax, rax
    jne failed
    mov rdi, r13
    mov rsi, r12
    mov edx, 2
    mov eax, 7
    int 0x80
    cmp rax, 2
    jne failed
    cmp byte ptr [r12], 65
    jne failed
    cmp byte ptr [r12 + 1], 66
    jne failed

    mov byte ptr [r12], 66
    mov byte ptr [r12 + 1], 65
    mov rdi, r13
    xor esi, esi
    mov edx, 2
    mov ecx, 1
    mov eax, 6
    int 0x80
    cmp rax, -14
    jne failed
    mov rdi, r13
    mov rsi, r12
    mov edx, 257
    mov ecx, 1
    mov eax, 6
    int 0x80
    cmp rax, -22
    jne failed
    mov rdi, r13
    mov rsi, r12
    mov edx, 2
    mov ecx, 2
    mov eax, 6
    int 0x80
    cmp rax, -3
    jne failed
    mov rdi, r13
    mov rsi, r12
    mov edx, 2
    mov ecx, 1
    mov eax, 6
    int 0x80
    test rax, rax
    jne failed
.ack:
    mov rdi, r13
    mov eax, 8
    int 0x80
    cmp rax, -11
    je .ack
    test rax, rax
    jne failed
    mov rdi, r13
    mov rsi, r12
    mov edx, 1
    mov eax, 7
    int 0x80
    cmp rax, 1
    jne failed
    cmp byte ptr [r12], 1
    jne failed
    mov rdi, r13
    mov eax, 9
    int 0x80
    test rax, rax
    jne failed
    mov rdi, r13
    mov eax, 10
    int 0x80
    cmp rax, -1
    jne failed
    mov edi, 37
    mov eax, 1
    int 0x80
failed:
    mov edi, 99
    mov eax, 1
    int 0x80
    ud2
