.intel_syntax noprefix
.section .text
.global _start
_start:
    jmp rdi                     // AUSP page is writable and NX
