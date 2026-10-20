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

## AUEX display API

The optional VirGL GPU API uses capability bit `4` from `AUSC1`.
`Gpu.Create(width, height)` (opcode 121) returns an opaque, process-scoped
handle for a texture up to 64×64, with one texture per process and four
globally. `Gpu.Destroy(handle)` (122), `Gpu.Clear(handle, rgb)` (123),
`Gpu.FillRect(handle, x, y, width, height, rgb)` (124), and
`Gpu.ReadPixel(handle, x, y)` (125) accept semantic values only. Stale or
foreign handles return `-13`; VirGL unavailability returns `-19` on create.
`Gpu.Blit(handle, x, y)` (126) also requires display capability bit `2` and
the display lease, and places that texture into an open compositor frame.
Exit and device reset revoke handles and release or safely quarantine DMA
backing. No API accepts raw VirGL bytes, physical addresses, or resource IDs.

`System.Australis.Display.Acquire()` claims the sole display lease for the
calling process (opcode 104). The kernel uses the caller's process record and
requires capability bit `2` from the read-only `AUSC1` manifest. A second
claim returns `-16`; a caller without the grant receives `-13`.
`Release()` (opcode 105) gives up the lease. Exit, fault, and termination also
release it, restore the framebuffer text mirror, and leave the serial
terminal contents intact. The framebuffer shows a recovery notice.

`FillRect(x, y, width, height, rgb)` (opcode 106) writes a 24-bit RGB color
inside the captured GOP mode. The entire rectangle must fit the mode, have
positive dimensions, and contain at most 65,536 pixels. Only the lease owner
can draw. Display geometry and format are available through SystemInfo
selectors `23`–`29`; no user call returns a framebuffer address.
`SetMode(width, height)` (opcode 107) returns `-95` for the fixed GOP
framebuffer after firmware handoff. A future native display driver may
implement mode switching behind this call.
`PollMouse(byte[3])` (opcode 108) returns `3` when a boot-mouse report is
available and `-1` when none is queued. The bytes hold buttons, X delta plus
128, and Y delta plus 128. Only the current display lease owner may poll;
other processes receive `-13`.
`CaptureKeyboard(enabled)` (opcode 109, with `enabled` equal to `0` or `1`)
selects whether USB keyboard bytes reach the display owner or the shell.
`PollKey()` (opcode 110) returns the next USB key byte or `-1` when none is
queued. Both calls require the display capability and current lease;
`PollKey()` also requires keyboard capture. Unauthorized callers receive
`-13`. Releasing the lease restores USB keyboard input to the shell.
COM1 input remains available to the shell throughout.

`BeginFrame()` (opcode 111) opens a compositor-owned RGB backbuffer for the
lease owner. `FillRect` updates that buffer and records clipped damage while a
frame is open. `PresentFrame()` (opcode 112) copies the accumulated dirty
rectangles to GOP as one submitted frame. Calling `BeginFrame` again before
presenting supersedes the open frame while retaining its damage, so pixels
already changed in the backbuffer are still delivered. An unsupported GOP
mode returns `-95`; presenting without an open frame returns `-22`. The
kernel enforces a 16 ms minimum interval between GOP frame completion and
the next `BeginFrame`; an early call returns `-11` without opening a frame.
The display service sleeps and retries while keeping its pending damage.
`Stats(byte[20])` (opcode 113) returns five little-endian unsigned 32-bit
values: submitted frames, presented frames, superseded frames, last frame
latency in microseconds, and maximum frame latency in microseconds. The
latency runs from `BeginFrame` through completed GOP writes. Counters reset
when a new process claims the display. All three calls require the display
capability and active lease; unauthorized callers receive `-13`.

`AllocateBuffer(width, height, strideBytes, format)` (opcode 114) returns a
positive owned handle for a full-screen RGBX8888 buffer (`format = 1`,
`strideBytes = width × 4`). A maximum of three buffers may be live. The
geometry must match the current display; invalid layouts return `-22`, an
exhausted pool returns `-12`, and an unauthorized caller gets `-13`.
`DestroyBuffer(handle)` (115) releases an available buffer. `BeginBuffer(handle)`
(116) moves it into the drawing state. `FillBufferRect(handle, x, y, width,
height, rgb)` (117) draws a checked RGB rectangle and tracks damage.
`SubmitBuffer(handle)` (118) presents the damage and returns a positive fence;
failed presentation returns `-5` and leaves the buffer drawable for retry.
An early submission under frame pacing returns `-11` without changing it.
`BufferCompletion(handle, fence)` (119) reports `1` when that submission is
complete. `ReleaseBuffer(handle, fence)` (120) returns it to the available
state. GOP completion is synchronous, but callers must still use the matching
fence to release a submitted buffer. A busy buffer cannot be redrawn or
destroyed. Handles and fences are invalidated on lease release or process
exit. All buffer calls require both display capability and the current lease;
no call exposes a kernel or framebuffer address.

The live `/System/Core/Display.exec` process owns the lease and accepts
version 2 channel submissions from two separate AUEX clients. A create
request is `[1,R,G,B]` and returns `[1,window ID]`. A cell update is
`[2,ID,column,row,R,G,B]` with column and row in `0..3`; it returns
`[2,1]` on success or `[2,0]` on denial. A close request is `[3,ID]`.
The service retains each client's 4×4 RGB cells and binds its ID to the
authenticated channel peer. Closing the channel removes that window.
The service sends pointer events `[4,ID,kind,xlo,xhi,ylo,yhi]`, where kind is
`1` for motion during capture, `2` for button down, and `3` for button up.
Coordinates are clipped to the receiving window's content. It sends key
events `[5,ID,key]` only to the focused client. Clicking wallpaper clears
focus and releases USB keyboard capture. The service owns window geometry
and stacking: title drags move windows, right and bottom edge drags resize,
and red, yellow, and green controls close, minimize, and toggle maximize.
The top bar restores minimized windows. Arbitrary client pixel surfaces
remain future work. Replies and input events share each client
channel, so a client must receive into a buffer large enough for the
seven-byte pointer frame even while waiting for a two-byte reply.

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
