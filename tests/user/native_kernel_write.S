.intel_syntax noprefix
.section .text
.global _start
_start:
    mov rax, 0x8000000000      // kernel-owned dynamic PML4 slot
    mov byte ptr [rax], 0x5a
    ud2
