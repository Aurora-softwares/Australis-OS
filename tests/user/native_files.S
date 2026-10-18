.intel_syntax noprefix
.section .text
.global _start
_start:
    lea r12, [rsp - 64]
    mov r14d, 10

    // A read handle cannot be promoted to write access, and the boot
    // volume cannot be opened writable.
    lea rdi, [rip + system_path]
    mov esi, system_path_end - system_path
    xor edx, edx
    mov eax, 11
    int 0x80
    cmp rax, 3
    jne failed
    mov r13, rax
    mov r14d, 11
    mov rdi, r13
    mov rsi, r12
    mov edx, 16
    mov eax, 12
    int 0x80
    cmp rax, 1
    jl failed
    mov r14d, 12
    mov rdi, r13
    lea rsi, [rip + contents]
    mov edx, 3
    mov ecx, 1
    mov eax, 13
    int 0x80
    cmp rax, -8
    jne failed
    xor edi, edi
    mov esi, 4
    xor edx, edx
    mov eax, 11
    int 0x80
    cmp rax, -14
    jne failed
    mov rdi, r13
    mov eax, 14
    int 0x80
    test rax, rax
    jne failed
    mov r14d, 13
    lea rdi, [rip + system_path]
    mov esi, system_path_end - system_path
    mov edx, 1
    mov eax, 11
    int 0x80
    cmp rax, -8
    jne failed
    mov r14d, 14

    // A bad destination must not advance a file handle.
    lea rdi, [rip + system_path]
    mov esi, system_path_end - system_path
    xor edx, edx
    mov eax, 11
    int 0x80
    cmp rax, 3
    jl failed
    mov r13, rax
    mov r14d, 15
    mov rdi, r13
    xor esi, esi
    mov edx, 1
    mov eax, 12
    int 0x80
    cmp rax, -14
    jne failed
    mov r14d, 16
    mov rdi, r13
    mov rsi, r12
    mov edx, 1
    mov eax, 12
    int 0x80
    cmp rax, 1
    jne failed
    mov rdi, r13
    mov eax, 14
    int 0x80

    // Create a durable data file. On a repeat run, replace its old contents.
    lea rdi, [rip + data_path]
    mov esi, data_path_end - data_path
    mov eax, 15
    int 0x80
    mov r14d, 17
    test rax, rax
    je .created
    cmp rax, -9
    jne failed
.created:
    lea rdi, [rip + data_path]
    mov esi, data_path_end - data_path
    mov edx, 1
    mov eax, 11
    int 0x80
    cmp rax, 3
    jl failed
    mov r13, rax
    mov r14d, 18
    mov rdi, r13
    xor esi, esi
    mov edx, 3
    mov ecx, 1
    mov eax, 13
    int 0x80
    cmp rax, -14
    jne failed
    mov rdi, r13
    lea rsi, [rip + contents]
    mov edx, 3
    mov ecx, 1
    mov eax, 13
    int 0x80
    test rax, rax
    jne failed
    mov r14d, 19
    mov rdi, r13
    mov eax, 14
    int 0x80
    test rax, rax
    jne failed

    lea rdi, [rip + data_path]
    mov esi, data_path_end - data_path
    xor edx, edx
    mov eax, 11
    int 0x80
    cmp rax, 3
    jl failed
    mov r13, rax
    mov r14d, 20
    mov rdi, r13
    mov rsi, r12
    mov edx, 3
    mov eax, 12
    int 0x80
    cmp rax, 3
    jne failed
    cmp byte ptr [r12], 65
    jne failed
    cmp byte ptr [r12 + 1], 66
    jne failed
    cmp byte ptr [r12 + 2], 67
    jne failed
    mov rdi, r13
    mov eax, 14
    int 0x80
    test rax, rax
    jne failed
    mov rdi, r13
    mov eax, 12
    int 0x80
    cmp rax, -1
    jne failed

    // Deliberately leave one descriptor open. The process exit path must
    // close it before the next run, whose first open expects descriptor 3.
    lea rdi, [rip + data_path]
    mov esi, data_path_end - data_path
    xor edx, edx
    mov eax, 11
    int 0x80
    cmp rax, 3
    jne failed

    lea rdi, [rip + success]
    mov esi, success_end - success
    mov eax, 3
    int 0x80
    mov edi, 37
    mov eax, 1
    int 0x80
failed:
    mov edi, r14d
    mov eax, 1
    int 0x80
    ud2
system_path:
    .ascii "/System/Config/capabilities.manifest"
system_path_end:
data_path:
    .ascii "/data/native-file-check"
data_path_end:
contents:
    .ascii "ABC"
success:
    .ascii "native-files: passed\n"
success_end:
