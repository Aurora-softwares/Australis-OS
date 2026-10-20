.intel_syntax noprefix
.section .text
.global _start
_start:
    // AUSP v2 starts at RDI; use the shared getpid and exit contracts.
    cmp dword ptr [rdi], 0x50535541
    jne invalid
    cmp dword ptr [rdi + 4], 2
    jne invalid
    mov eax, dword ptr [rdi + 20]
    cmp byte ptr [rdi + rax], 47
    jne invalid
    mov eax, 99
    int 0x80
    cmp rax, -38
    jne invalid
    mov eax, 2
    int 0x80
    mov edi, eax
    mov eax, 1
    int 0x80
    ud2
invalid:
    mov edi, 99
    mov eax, 1
    int 0x80
    ud2
