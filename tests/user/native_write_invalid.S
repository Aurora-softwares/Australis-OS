.intel_syntax noprefix
.section .text
.global _start
_start:
    mov rbx, rdi                 // AUSP data page
    mov rdi, 0xffff800000000000 // supervisor address
    mov esi, 1
    mov eax, 3
    int 0x80
    cmp rax, -14
    jne invalid

    lea rdi, [rbx + 4095]       // range crosses out of the AUSP page
    mov esi, 2
    mov eax, 3
    int 0x80
    cmp rax, -14
    jne invalid

    mov rdi, rbx
    mov esi, 257                // exceeds the per-call limit
    mov eax, 3
    int 0x80
    cmp rax, -22
    jne invalid

    lea rdi, [rip + passed]
    mov esi, passed_end - passed
    mov eax, 3
    int 0x80
    cmp rax, passed_end - passed
    jne invalid
    mov edi, 17                 // distinct success status for the boot harness
    mov eax, 1
    int 0x80
    ud2
passed:
    .ascii "native-invalid-pointers-ok"
passed_end:
invalid:
    mov edi, 99
    mov eax, 1
    int 0x80
    ud2
