.intel_syntax noprefix
.section .text
.global _start
_start:
    xor eax, eax
    mov rax, qword ptr [rax]
    ud2
