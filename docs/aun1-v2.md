# AUN1 native user image, version 2

This is the small x86-64 ring-3 contract implemented by the Australis loader
and Hydrogen's `type = "native"` project target. It is deliberately limited to
one code page, terminal output, PID lookup, and exit. AUEX remains a separate
interpreted application format.

## Image

All multibyte fields are little endian. The file is exactly 16 bytes plus
`code_length` bytes; there is no trailing data or relocation table.

| Offset | Size | Field | Required value |
| --- | ---: | --- | --- |
| 0 | 4 | Magic | ASCII `AUN1` |
| 4 | 2 | `code_length` | 1 through 4096 |
| 6 | 1 | Version | 2 |
| 7 | 1 | Flags | 0 |
| 8 | 2 | Entry offset | 0 |
| 10 | 2 | Data length | 0 |
| 12 | 4 | Reserved | 0 |

The loader rejects nonzero reserved fields, invalid lengths, and files whose
actual length differs from the header. The previous eight-byte AUN1 header
(version byte 0) remains accepted for existing native fixtures. New compilers
must emit version 2.

## Entry and memory

The OS copies the code into a private user page and enters at its first byte.
The code page is user readable and executable, but not writable. Inline
literals are addressed relative to RIP; there are no relocations or fixed
virtual addresses. `RDI` points to the `AUSP` version 2 startup record in a
separate user data page. `RSP` starts at the top of one writable user stack
page. The intervening page is unmapped as a guard. The data and stack pages
are non-executable. The kernel mappings in the private page table are
supervisor only. This version provides no general heap or writable image data.

The startup record's argument, environment, and directory references are
offsets relative to the record, as described in the userland guide. The first
Hydrogen source profile does not inspect them. Applications must not assume a
particular user base address.

## `int 0x80` calls

Set `RAX` to the number. The result is returned in `RAX`; `RCX` may be
clobbered. Other general registers are preserved for returning calls.

| Number | Arguments | Result |
| ---: | --- | --- |
| 1, exit | `RDI` = signed exit status | Does not return; shell records the status |
| 2, getpid | None | Positive process ID |
| 3, terminal write | `RDI` = user byte pointer, `RSI` = length | Bytes written, or a negative error |

Terminal write accepts 0 through 256 bytes in one call. For nonempty writes,
the complete range must fit inside one of the mapped code, startup-data, or
stack pages. The kernel checks the range before reading any byte. A bad range
returns `-14`; a length above 256 returns `-22`; a serial transmit timeout
returns `-5`. A zero-length write returns zero. This initial service writes to
the primary COM1 serial terminal and does not mirror to the framebuffer.
Unknown call numbers return `-38`. A child that faults is terminated and the
parent shell and KMon remain available.

Hydrogen currently lowers only a flat `static Main(string[] args)` body with
ASCII literal `System.Australis.Terminal.Write(...)` calls and a literal return
status for this target. Other source constructs fail compilation rather than
producing an image with different semantics.

## QEMU integration proof

From the Australis OS repository, run `make test-native-user-mode`. The target
builds the Hydrogen source fixture as AUN1 v2, packages it in the HyFS 2 ISO,
and boots the image with AHCI and NVMe separately. On each boot the harness
checks the source program's terminal marker and exit status, the PID syscall,
rejected supervisor and page-crossing pointers and oversized writes, contained
page and privilege faults, continued PID 1 shell commands, and KMon recovery.
