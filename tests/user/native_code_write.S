.intel_syntax noprefix
.section .text
.global _start
_start:
    lea rax, [rip + _start]
    mov byte ptr [rax], 0x90
    ud2
