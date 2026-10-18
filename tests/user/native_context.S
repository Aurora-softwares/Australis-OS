.intel_syntax noprefix
.section .text
.global _start
_start:
    mov rbx, rdi
    mov byte ptr [rbx + 4000], 0x5a
    mov r12d, 0x12345678
    mov ecx, 3000000
.busy:
    pause
    dec ecx
    jnz .busy
    cmp r12d, 0x12345678
    jne .invalid
    cmp byte ptr [rbx + 4000], 0x5a
    jne .invalid
    mov edi, 29
    mov eax, 1
    int 0x80
    ud2
.invalid:
    mov edi, 99
    mov eax, 1
    int 0x80
    ud2
