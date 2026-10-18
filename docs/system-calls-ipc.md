# System calls and IPC (Phase 4)

The supported AUN1 user profile enters the kernel through `int 0x80` from
ring 3. AUEX compatibility programs use checked interpreter opcodes. Both
paths use the same kernel-owned process records and bounded channel table.

## Native ABI version 1

Set `RAX` to the call number. The result replaces `RAX`; other general
registers are preserved except that the legacy terminal-write call may
clobber `RCX`. Call 4 returns ABI version `1`. Unknown calls return `-38`.
Native calls use a maximum of 256 bytes per message and never follow a user
pointer in the kernel address space.

| Call | Arguments | Result |
| ---: | --- | --- |
| 1 | `RDI` exit status | Does not return |
| 2 | None | Positive PID |
| 3 | `RDI` bytes, `RSI` length | Serial bytes written |
| 4 | None | ABI version `1` |
| 5 | `RDI` channel protocol version | Invited channel handle, or `-1` until open |
| 6 | `RDI` handle, `RSI` bytes, `RDX` length, `RCX` protocol version | Send: `0` on success |
| 7 | `RDI` handle, `RSI` destination, `RDX` capacity | Received byte count, or `-1` if empty |
| 8 | `RDI` handle | `0` when readable, `-11` when empty |
| 9 | `RDI` handle | Close: `0` on success |
| 10 | `RDI` handle | Peer PID |
| 11 | `RDI` path, `RSI` path bytes, `RDX` mode (`0` read, `1` write) | File descriptor `3`–`15` |
| 12 | `RDI` descriptor, `RSI` destination, `RDX` capacity | File bytes read; `0` at EOF |
| 13 | `RDI` descriptor, `RSI` source, `RDX` length, `RCX` operation (`1` replace, `2` append) | `0` on success |
| 14 | `RDI` descriptor | Close file: `0` on success |
| 15 | `RDI` path, `RSI` path bytes | Create empty file: `0` on success |
| 16 | `RDI` path, `RSI` path bytes | Delete file: `0` on success |

Errors are negative: `-14` invalid user range, `-22` invalid argument or
length, `-38` unknown call, `-11` no message for call 8, `-1` absent channel
or message, `-2` denied process or handle, `-3` protocol version mismatch,
`-4` destination too small, and `-5` full queue or serial timeout. A failed
copy does not consume a message or advance a file read. Zero-length buffers are valid. Nonempty
buffers must fit wholly within one mapped user code, data, or stack page;
receive destinations must be writable data or stack memory. Address arithmetic
is checked before conversion to a page index. The kernel copies through the
process-owned physical frame after restoring kernel page tables. File paths
must be absolute, contain 1–255 bytes, and fit in one readable user page.
File transfer lengths are limited to 256 bytes per call. File errors are
negative `VfsStatus` values (`-8` read-only, `-9` already exists, `-12` stale
handle, etc.); invalid pointers and syscall arguments still use `-14` and
`-22`. Applications can use repeated reads and appends for larger files.

## Handles, synchronization, and authorization

The channel table contains at most 16 channels with four queued messages per
channel. Each message is at most 256 bytes. Handles include a generation so a
closed channel cannot name a newly allocated channel in the same slot. Every
operation checks the caller PID against the channel endpoints. The AUEX
parent opens a channel only to its live direct child and only when its process
record has capability bit `1`, granted by the read-only `AUSC1` manifest.
The native child can accept only an invitation addressed to its PID. AUEX
`Channel.Wait` blocks the caller for a bounded number of scheduler rounds;
native call 8 provides a nonblocking readiness check. Closing or exiting
either endpoint invalidates the handle and discards queued messages.

AUEX and AUN1 file descriptors are held in separate per-process arrays.
Native descriptors are allocated from `3`–`15`; a PID can only address its own
table, and exit, fault, or termination closes its entries. Opens encode read
versus write access. A read handle cannot replace or append, and write opens
on the boot and USB mounts fail. The writable HyFS 2 `/data` mount remains
the only persistent write target. VFS mount and mutation generations reject
stale handles after unmount or a conflicting mutation. Native calls have no
direct driver access.

## Verification

`make test-stage5-host` covers process and channel records. `make
test-userland-stage5-ipc` covers successful AUEX exchange and denied channel
creation. `make test-native-user-mode` boots AHCI and NVMe, checks the ABI
version, a cross-format AUEX/AUN1 exchange, bad pointers and lengths, a
protocol mismatch, channel closure, native faults, and continued shell and
KMon operation.
`make test-native-files` boots a disposable `/data` disk on each controller,
checks read-only policy, bad destinations, replacement, descriptor closure,
18 process runs per boot, reboot persistence, and an offline HyFS 2 integrity
scan.
