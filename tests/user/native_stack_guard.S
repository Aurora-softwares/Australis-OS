.intel_syntax noprefix
.section .text
.global _start
_start:
    lea rax, [rsp - 4097]       // byte immediately below the stack page
    mov byte ptr [rax], 0x5a
    ud2
