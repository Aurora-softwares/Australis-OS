.intel_syntax noprefix
.section .text
.global _start
_start:
    xor edx, edx
    xor ecx, ecx
    mov eax, 1
    div ecx
    ud2
