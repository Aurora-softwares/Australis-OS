<div align="center">

<img src="assets/australis.icon.svg" width="30%" />

# Australis OS

</div>

Australis OS is an x86_64 freestanding kernel booted from a UEFI ISO. The
Hylang bootloader loads the separate raw `KERNEL.BIN`, captures the final
memory map, leaves boot services, prepares paging and interrupts, switches to
a kernel stack, and calls the kernel entry. The kernel uses no firmware API.
The Australis bootloader starts silently by default. During the two-second
boot window, press `D` for boot diagnostics, `N` for normal early status
messages, `R` for Rescue, or `S` to select Silent explicitly.
Boot errors remain visible in every mode.

With debug mode selected, the firmware console shows handoff diagnostics:

```text
[BOOT:DEBUG] AUKR kernel validated.
[BOOT:DEBUG] GOP framebuffer captured.
[BOOT:DEBUG] Exiting UEFI boot services.
```

The self-hosted compiler emits the bootloader as PE32+ and the kernel as an
`AUKR` raw image without C#, bflat, an assembler, or a linker. The kernel
executes a compiled `KernelMain.Run(long bootInfo)` method graph after the
bootloader calls `ExitBootServices`. It uses
freestanding memory intrinsics, page-backed object/array allocation, and live
Hylang AHCI or NVMe drivers to validate GPT, mount a read-only HyFS root, and
read files through the VFS. A COM1 interrupt receive ring runs the initial user
shell registry with `help`, `echo`, `ls`, `cat`, `devices`, `mounts`, `pwd`,
`path`, `run`, `ps`, and `version`. The console supervisor owns devices and privileged
services; checked AUEX programs use terminal and file-descriptor syscalls.
The bootstrap still has
limits described below; it is not yet a general-purpose OS.

For the current development version, release status, and planned version
targets, see the [versioning guide](VERSIONING.md).

## Requirements

- A built self-hosted Hylang compiler
  (`hy` by default), or set
  `HYDROGEN=/path/to/hy`.
- `mtools` (`mformat`, `mmd`, and `mcopy`).
- `xorriso`.
- For running the image: `qemu-system-x86_64` and OVMF firmware. The default
  firmware path is `/usr/share/OVMF/OVMF_CODE_4M.fd`.

Build the compiler first if necessary:

```bash
cd ../Hylang-Compiler
cmake -S . -B build
cmake --build build --target hydrogen_stage1
```

## Build

From this repository:

```bash
make build
make iso
```

For one command that also rebuilds applications, use `make all`. `make iso`
is an alias for `make iso-hyfs2`; both create the same HyFS2 ISO.
Use `make all` or two shell commands (`make build && make iso`) after changing
kernel sources. In `make build iso`, Make reads the packaging input signature
before the build runs, so that single invocation can reuse an older ISO.

`src/australlis.hyproj` is a Hydrogen `os` project referencing the bootloader
and kernel projects. The bootloader uses `type = "efi"`; the kernel uses
`type = "kernel"`. Hydrogen builds the bootloader as a UEFI application and
the kernel as a raw binary. Each manifest's `output` field places the artifact
in the EFI tree.
You can invoke the compiler directly:

```bash
hy build src/australlis.hyproj -o build/efi
```

`make build` runs that command. `make iso` builds and bundles these files:

```text
build/efi/EFI/BOOT/BOOTX64.EFI
build/efi/EFI/AUSTRALIS/KERNEL.BIN
build/boot/root.hyfs2.img
build/australis-hyfs2.iso
```

The bootloader reads `KERNEL.BIN` from the same FAT volume, validates its
`AUKR` header and exact size, and places it in executable loader memory before
the final memory-map capture. After `ExitBootServices`, it switches to a
dedicated 64 KiB kernel stack and enters the raw code. The former unused
`SYSTEM.EFI` placeholder is no longer packaged. The kernel starts the minimal
userland manager `/System/Core/System.exec` as PID 1 on normal boot.
The raw header is 16 bytes: `AUKR`, version `1`, code length, and entry offset
`16`, all little endian. The code is position independent.
The ISO is hybrid: it contains an El Torito UEFI boot entry for optical media,
a GPT EFI System Partition, and a 4 MiB read-only HyFS 2 partition for the
kernel root. Hydrogen compiles the projects in `applications/Applications.hyproj`
directly to `.exec` files in the generated root tree, then
`tools/make_hyfs2_image.py` packs it into that partition. Its GPT type GUID is
`9f5eb82e-692e-5a8f-b968-adaaa349dd93`.
The ISO can also be written directly to a USB drive or disk. It is not a
virtual-disk format.

HyFS 1 remains available for compatibility and recovery testing. Build its
separate image with `make iso-hyfs1`; it is written to
`build/australis-hyfs1.iso` and does not replace the default HyFS 2 image.

Write the ISO byte-for-byte to the target drive; do not copy its files onto an
existing filesystem. This replaces that drive's contents. The target must boot
64-bit UEFI applications. Secure Boot must be disabled because the EFI
applications are not signed.

A standalone raw FAT image is also available through:

```bash
make image
```

at `build/australis-hylang-uefi.img`. That FAT-only image contains the EFI
programs; use the hybrid ISO for the live HyFS root.

## Run

```bash
make run
```

This boots `build/australis-hyfs2.iso` in QEMU with OVMF as optical media and
attaches the same image as an AHCI disk for the kernel's live HyFS root. The
QEMU window sends keyboard and mouse input through emulated xHCI devices. To
boot directly from the image's GPT EFI partition on AHCI, run:

```bash
make run-disk
```

`make run-disk` also attaches the xHCI USB keyboard and mouse. For the NVMe
storage path, run `make run-nvme`; it provides the same display and input. The
ISO remains optical boot media while the same image is attached as an NVMe
namespace.

The windows and cursor are framebuffer graphics. The current command shell
uses COM1; run `make run-gop` to see its output in the launching terminal
while the QEMU window shows the graphics demo. Click a window's content to
focus it and send USB keyboard input to that client. Click the wallpaper to
return USB keyboard input to the command shell. COM1 remains available to
the shell while a window is focused. If the display service stops, the
framebuffer shows a recovery notice and the COM1 shell stays available.
Drag a title to move its window, drag the right or bottom edge to resize,
and use the red, yellow, and green circles to close, minimize, and toggle
maximize. The coloured chips at the right of the top bar restore minimized
windows.

Click the QEMU display once so it captures keyboard and mouse input. QEMU's
default key combination for releasing the pointer and keyboard is Ctrl+Alt+G.

For the normal userland command shell in the terminal, run:

```bash
make run-serial
# or: make run-nvme-serial
```

To attach the ISO as a second read-only USB mass-storage volume and use COM1
for the shell, run `make run-usb-storage` (AHCI boot root) or
`make run-usb-storage-nvme`. The removable HyFS volume appears at `/usb`; use
`ls /usb` and `cat /usb/hello.txt` to inspect it. KMon also has `devices` and
`mounts`. The normal removable-media fixture uses HyFS 2 because it attaches
the default ISO.

Wait for `australis> `, then type `help`. `ls` lists the HyFS root and
`cat /hello.txt` reads a file from the mounted AHCI or NVMe device. The
userland shell handles quoted arguments, relative paths, `cd`, `pwd`, and
eight entries of command history. `set`, `export`, and `unset` manage child
environment values; `path` edits the executable search path. `exit` or
terminal Ctrl-D returns to KMon. The kernel recovery
console also accepts Enter, Backspace/Delete, arrow keys, Home/End,
Ctrl-A/Ctrl-E, Ctrl-C, Ctrl-L, and Ctrl-U. Its line buffer holds 256 bytes.
Namespace paths canonicalize repeated `/`, `.`, and `..`, and cross the
removable mount at `/usb`. Compatibility HyFS 1 images remain limited to flat
32-byte names. KMon's built-in `cat` accepts files up to 64 KiB. The UART
uses COM1 at 115200 baud, 8 data bits, no parity, and one stop
bit. Its PIC IRQ4 handler copies received data into a 1024-byte kernel ring,
then the shell drains that ring after it wakes. A full ring drops new input and
records the drop count in `KernelBootInfo`.

KMon can launch the packaged `cat.exec` when a root filesystem is mounted.
To launch it explicitly from KMon, run:

```text
kmon> run cat /hello.txt
Hello from Australis HyFS.
```

`/System/Bin/cat.exec` reads a dynamic path through checked file calls and handles
EOF and file errors. `make test-userland-essentials` runs bare `cat` in the
userland shell on AHCI and NVMe, together with the other Essentials commands.
Bare `cat` in KMon also resolves the packaged executable through its search
path; early Rescue has no filesystem-backed `cat` command.

`run /System/Bin/user-fault.exec` in KMon exercises the protected-write failure path.
`ps` reports the most recent program state.

For the post-handoff framebuffer console, run QEMU with OVMF and its standard
VGA device:

```bash
make run-gop
```

This opens QEMU's graphical window with an EFI Graphics Output Protocol (GOP)
framebuffer. Type shell commands into the launching terminal's COM1 session;
the framebuffer mirrors output and scrolls as it fills. The QEMU window's USB
keyboard and the launching terminal's COM1 session both edit the same command
line. VT-x/KVM is optional: without it QEMU uses software
emulation, which is slower but has the same GOP behavior.

Override the
default locations when needed:

```bash
make run HYDROGEN=/path/to/hy OVMF_CODE=/path/to/OVMF_CODE.fd
```

## Scope

The UEFI bootloader target supports `System.Uefi.ClearScreen()` before console output,
`System.Uefi.Await()` to wait for and consume one keyboard event, literal console
lines, `System.Kernel.Boot.Load(<literal-path>)` for the raw image, and the handoff
sequence:
`System.Uefi.ExitBootServices()`, `System.Kernel.MemoryMap.Initialize()`,
`System.Kernel.Memory.Initialize()`, `System.Kernel.VirtualMemory.Initialize()`,
`System.Kernel.VirtualMemory.ApplyPolicy()`, optional
`System.Kernel.Memory.AllocatePage()` calls,
`System.Kernel.Heap.Initialize()`, optional
`System.Kernel.Heap.Allocate(<literal-byte-count>)` calls,
`System.Kernel.Framebuffer.Initialize()`, literal
`System.Kernel.Framebuffer.WriteLine(<text>)` calls, and
`System.Kernel.Halt()`. An interrupt-enabled kernel additionally uses the
ordered sequence `System.Kernel.Gdt.Initialize()`,
`System.Kernel.Idt.Initialize()`, `System.Kernel.Interrupts.Initialize()`,
`System.Kernel.Timer.Initialize()`, optional
`System.Kernel.Pci.Initialize()`, `System.Kernel.Mmio.Initialize()`,
`System.Kernel.Dma.Initialize()`, literal
`System.Kernel.Dma.AllocatePages(<1..1024>)` calls,
`System.Kernel.Runtime.Execute()`. The kernel enables interrupts and runs its
own idle loop after the raw entry is called.
`BOOTX64.EFI` captures a final UEFI memory map,
reserves space for 64 additional memory descriptors, then retries the
`GetMemoryMap`/`ExitBootServices` pair up to eight times if firmware changes the
map key. It initializes its physical-page allocator after the successful
handoff. The allocator selects the largest
`EfiConventionalMemory` region, reserves and clears its first 4 KiB page for
metadata, then publishes the remaining page range. Virtual-memory initialization
copies every present PML4, PDPT, PD, and PT page into allocator-owned pages, then
loads the new root into `CR3`. Leaf mappings retain their existing physical
frames and attributes. The `KernelBootInfo` record and its `RDI` pointer survive
the handoff. Console output stops at the handoff because it depends on firmware
services. The first mapping policy leaves virtual page zero unmapped. It splits
only the first 1 GiB or 2 MiB firmware leaf when needed, preserving the remaining
leaf mappings and their cache attributes, then invalidates any cached translation
for virtual page zero. `AllocatePage()` reserves and clears a
4 KiB page, advances the allocator cursor, and publishes the page address in
`KernelBootInfo`. `Heap.Initialize()` reserves its first physical page and
creates a zero-filled, 16-byte aligned bump range. `Heap.Allocate()` accepts a
literal size from 1 through 1 MiB, grows the range with contiguous physical
pages, and publishes the allocation address in `KernelBootInfo`. This bootstrap
heap is monotonic: it does not free or reuse allocations. The framebuffer
console locates GOP before firmware services end, records its framebuffer data,
then clears and writes pixels directly from the post-handoff kernel. It supports
the standard RGB and BGR 32-bit GOP pixel formats and printable ASCII literals.
The mode stays fixed after handoff. User programs can query validated width,
height, stride, format, depth, and mode flags through system-information API 5;
the physical framebuffer address is not exposed.

After entry, `PhysicalPages.AllocateZeroed` and `PhysicalPages.Free` provide a
checked reusable 4 KiB page pool for explicit kernel owners. `KernelAddressSpace`
maps and unmaps explicit pages only in an unused lower-half PML4 slot, preserves
the bootstrap hierarchy, rejects large bootstrap leaves, invalidates the local
TLB after each change, and sets NX on every dynamic data mapping. Managed
objects, arrays, and strings can release their owned page spans individually
through `System.Kernel.Managed.Release`.

The interrupt sequence installs a ring-0 GDT, then an IDT with dedicated stubs
for CPU exceptions, legacy PIC vectors `0x20`–`0x2f`, local-APIC timer vector
`0x30`, storage vector `0x31`, and reusable device vector `0x32`. CPU
exceptions enter a common allocation-free panic path. It disables interrupts,
captures the error code, return frame, `CR2`, and all general registers, then
writes the same hexadecimal report directly to polled COM1 and the GOP
framebuffer before halting. In `D` Debug boot, KMon's `panic` command
deliberately reads the protected null page; `panic gp` accesses a noncanonical
address to exercise general-protection classification under QEMU. See the
[kernel reliability contract](docs/kernel-reliability.md) for ownership rules
and report interpretation.
The PIC is remapped and masked, so it cannot deliver device IRQs before a driver
has registered ownership. The local APIC is enabled in either xAPIC or x2APIC
mode; xAPIC receives an uncached identity mapping when its page is absent from
the cloned firmware hierarchy. The timer runs periodically and increments a raw
monotonic tick counter. The kernel calibrates the TSC against a 50 ms PIT
channel-2 interval and gives AHCI, NVMe, and future USB work checked deadlines.
The reusable device stub acknowledges a registered W1C status register and
only queues completion metadata; command work remains outside the IRQ handler.

`Pci.Initialize()` scans every PCI bus, device, and function through
configuration mechanism #1 (`0xcf8`/`0xcfc`) and records the first xHCI, AHCI,
and NVMe controllers. `Mmio.Initialize()` reads their memory BARs and maps a
fixed 64 KiB high virtual aperture for each valid controller BAR. The kernel
then probes the complete xHCI BAR size with memory decode disabled, restores
the PCI command and BAR values, and maps the complete range into its owned
lower-half aperture. BAR physical addresses above 4 GiB are supported. These
leaves are writable, non-cacheable (PCD/PWT), and non-executable.
`Dma.Initialize()` selects the largest usable conventional-memory interval below
4 GiB and reserves the literal DMA requests emitted in this kernel from its
high end. It removes that slice from the main physical allocator when both use
the same descriptor. `Dma.AllocatePages()` returns contiguous, zero-filled
physical pages from the reserved slice and records the latest allocation. This
bootstrap has no IOMMU programming yet. The live image reserves 64 contiguous
pages: storage owns the first sixteen and a checked runtime allocator manages
the remaining forty-eight. Each allocation has explicit ownership, supports
individual release and reuse, and uses memory fences when ownership crosses
the CPU/device boundary. The allocator rejects configurations that require
IOMMU translation until translation support exists.

`Storage.Initialize()` prefers a mapped NVMe controller and uses AHCI when NVMe
is absent. The NVMe path uses the 16-page DMA allocation for depth-two admin
and I/O queues, a single-page PRP buffer, and the GPT transfer buffer. It
enables PCI bus-master DMA, resets the controller with bounded polling,
identifies namespace 1, creates I/O queues, and issues one-sector polling reads.
The AHCI path stops the selected SATA port engine, installs its command list,
received-FIS area, command table, and data buffer, then issues polling ATA READ
DMA EXT commands. Both paths read LBA 0 for the MBR, LBA 1 for the GPT header,
and the primary GPT entry
array from the LBA recorded in that verified header. The emitted path checks
the MBR signature and protective entry, the GPT 1.0 signature, exact 92-byte
header, header CRC-32, and entry-array CRC-32. It accepts 512-byte logical
sectors and standard 128-byte GPT entries, with a bounded maximum of 256
entries. The first present GPT partition is published in `KernelBootInfo` for
boot diagnostics. The raw kernel independently reads the GPT, selects the
HyFS partition by its full type GUID, and mounts it through the VFS.

The paging-hierarchy copier targets the normal four-level x86_64 paging mode. It
detects an active five-level (LA57) hierarchy and halts before changing `CR3`.

The generated EFI bootloader uses a zero image base and RIP-relative internal
references, so firmware can load it at an available address. It is
tested as both an El Torito ISO and a hard disk image under OVMF. Physical
hardware validation still requires booting a test USB or disk on each firmware
family that Australis intends to support.

## USB driver work

`src/kernel/usb/UsbDrivers.hy` contains the first Hylang USB driver layer: PCI
xHCI class discovery, a bounded xHCI stop/reset sequence, safe configuration
descriptor selection, USB mass-storage Bulk-Only Transport CBW/CSW and a
synchronous SCSI READ(10) transaction over an injected bulk transport, and
boot-protocol keyboard/mouse report decoding with a basic US keymap.
Run its simulated PCI, register, descriptor, storage, and HID checks with:

```bash
make test-usb
```

The kernel owns one live xHCI controller with up to two root-port devices. It
configures MSI or MSI-X vector `0x32`, initializes DCBAA and scratchpads plus
command, event, EP0, interrupt, and bulk rings, then enumerates up to two of a
boot keyboard, boot mouse, and read-only USB mass-storage device. Keyboard reports enter
the same normal-context console path as COM1. Mouse reports enter a bounded
kernel event queue with signed motion and button state. The user display
service draws a software cursor, routes button and key events to its
focused client, and owns live window movement, resizing, stacking, and
controls. USB storage uses
BOT and SCSI READ CAPACITY,
REQUEST SENSE, and READ(10), exposes the common block-device interface, and can
mount a second read-only HyFS volume at `/usb`. Disconnects, stalls, transfer
failures, and unit-attention responses have bounded recovery while COM1 and the
boot root remain available. Two-device operation requires two controller slots
and enough reserved DMA; hubs, more than two devices, non-US layouts, and
writable removable media remain later work.

The live keyboard matrix is `make test-stage3`; `make test-mouse` covers a live
boot mouse on both storage paths. The AHCI and NVMe USB-storage
matrix is `make test-stage4`. `make test-xhci-multi` covers simultaneous
keyboard/storage and keyboard/mouse devices on both storage paths, including
removal and reconnect.
The complete Phase 5/6 regression set is `make test-phase5-6`; supported
hardware and failure coverage are listed in
[`docs/storage-driver-stability.md`](docs/storage-driver-stability.md).

## AUEX `.exec` user programs

AUEX v1 is Australis's first user program format. Files use the `.exec`
extension defined in `src/README.md`; `AUEX` remains the internal format
magic and ABI name. Its 32-byte little-endian
header contains `AUEX`, version and header size, code length, initialized data
length, data capacity, entry offset, and separate CRC-32 values for code and
data. The image exposes a read-only code region at `0x400000` and a bounded
read/write data region at `0x500000`.

The interpreter provides exit, terminal read/write, checked file and directory
calls, metadata queries, checked byte stores, cooperative yield operations,
fixed scalar locals, bounded byte arrays, local method calls, a checked
expression stack, signed arithmetic, comparisons, and branches. Hylang `if`,
`while`, and `for` statements compile to these operations, including `break`,
`continue`, short-circuit Boolean logic, numeric output, and computed exit
codes. Division by zero is reported as an application arithmetic fault. Descriptors
0, 1, and 2 have canonical terminal semantics; mounted files use descriptors
3 through 15.
Every user pointer is range checked and copied through `UserAddressSpace`, so
an AUEX instruction cannot name kernel physical memory or modify its code.
The scheduler applies an instruction limit and closes descriptors on exit,
fault, or exhaustion.

Bundled programs are Hylang `type = "exec"` projects under `applications`.
The compiler lays out their literals and read buffer, emits AUEX bytecode, and
writes both CRCs. `applications/README.md` lists the supported source calls and
the aggregate project workflow for applications kept in separate repositories.
Use `make iso APPLICATIONS_PROJECT=/path/to/MyApplications.hyproj` for another
source aggregate, or pass ready artifacts through `APPLICATION_ARTIFACTS`.

This is software enforced isolation for the AUEX instruction set. A native
x86-64 ring-3 path with bounded memory is also available for read-only system images;
native IPC and file calls use checked copies and process-owned handles.
Broader terminal and device APIs remain AUEX-only. Native children use timer-driven scheduling and the shared
spawn/wait/terminate lifecycle.

### Native AUN1 programs

An `AUN1` `.exec` file under `/System/Bin` contains an eight-byte header:
`AUN1`, a little-endian 16-bit code length, and two zero reserved bytes. One
code page is permitted. `run /System/Bin/name.exec` starts it in a private
page table, with read-only executable code, a writable non-executable startup
page, a writable non-executable stack, and unmapped guards on both sides of
the stack. The data page is present and zeroed even for native launches
without a startup record, so syscall pointer validation matches the mapping.
The kernel mappings remain supervisor-only. The native child receives an
`AUSP` v2 startup record in `RDI`; its layout matches the AUEX start record,
but the argument, environment, and working-directory entries are offsets from
`RDI` because native addresses are 64-bit. `RAX=1` with `RDI=exit status`
exits through `int 0x80`; `RAX=2` returns the child PID, `RAX=3` writes bounded
serial output, `RAX=4` reports ABI version 1, and calls 5–10 operate on
invited channels. Calls 11–16 provide bounded VFS file access with
process-owned descriptors. Unknown syscall numbers return `-38`. User page,
general-protection, invalid-opcode, and divide faults
finish only that child, release its pages, and preserve the parent shell and
KMon recovery path. See `docs/memory-protection.md` for the Phase 2 contract.

Run `make test-native-user-mode` for the AHCI and NVMe ring-3 matrix, including
native image launch, PID/exit, kernel-memory denial, code and data page
permissions, stack guards, privileged-instruction denial, and parent/recovery
continuity. The periodic timer preempts AUN1 children and the process host can
spawn, wait on, and terminate multiple native children. See
`docs/process-scheduling.md` for lifecycle and resource limits. AUN1 execution
is currently restricted to the read-only system bin directory; see
`docs/system-calls-ipc.md` for its checked channel and file ABI and remaining native
service limits.

The planned OS layer keeps the kernel, system userland, and application
userland separate. The GUI is an optional userland subsystem. See
`src/README.md` for the runtime and package model,
`src/userland/system/README.md` for the PID 1 contract, and
`src/userland/README.md` for the staged roadmap. The kernel console remains
the recovery shell until the userland shell and system manager pass their exit
tests.

Run the hosted runtime suite and live AHCI/NVMe matrix with:

```bash
make test-stage5
```

## Storage protocol layer

`src/kernel/storage/BlockDevice.hy` defines the synchronous block-device
contract used by every storage transport. A request has a positive sector count,
valid 512, 1024, 2048, or 4096-byte logical sector geometry, an in-range LBA,
and enough destination space. Each `Read` is all-or-nothing: a transport failure
never reports a partial request as successful.

`Ahci.hy` implements active SATA-port detection, bounded command-engine
stop/start sequencing, ATA IDENTIFY parsing, and physical-addressed IDENTIFY and
READ DMA EXT command layouts. `Nvme.hy` implements controller-ready checks,
doorbell stride decoding, standard 4 KiB-page controller configuration,
Identify and Read commands, and namespace geometry parsing. Its `NvmeController`
implements the block transport over injected registers and DMA pages for
host-side queue and failure testing. `Partitions.hy`
validates protective MBR entries and GPT 1.0 headers plus entry-array CRC-32
before it returns a usable partition.

Run the executable Hydrogen protocol tests with:

```bash
make test-storage
make test-kernel-panic
make test-stage2
make test-stage2-boot
make test-stage3
make test-stage4
make test-stage5
make test-ahci
make test-nvme
make test-nvme-controller
make test-nvme-boot
make test-ahci-boot
make test-partitions
make test-vfs
make test-hyfs
make test-hyfs1
make test-terminal
make test-graphics
make test-display-ahci
make test-display-nvme
make test-display-fallback
make test-serial-ahci
make test-serial-nvme
```

`make test-stage2` stress tests deadlines, vector ownership, deferred-event
overflow, PCI BAR probing, and DMA allocation/release on the host. The Stage 2
QEMU target boots both AHCI and NVMe with `qemu-xhci`, verifies the retained full
BAR mapping and calibrated clock, then repeats root reads while checking that
page, DMA, and MMIO ownership remain stable.

The boot emitter initializes either controller when `Main` calls
`System.Kernel.Storage.Initialize()`. The compiled Hylang method graph then
reinitializes the selected AHCI or NVMe controller through direct MMIO and DMA
adapters, reads through `BlockDevice`, and verifies both GPT CRCs through
`GptDisk`. `make test-nvme-boot` and `make test-ahci-boot` then verify the live
HyFS mount and checksummed reads of `/hello.txt` and the multi-sector
`/readme.txt` under QEMU Q35/OVMF. Physical controller validation remains
outstanding. The serial smoke tests send commands over COM1 and verify line
editing, root listing, file content, errors, and the prompt on both controllers.
They verify PIC IRQ4 delivery, an empty receive ring after repeated reads, and
that those reads return the page-allocation cursor to its shell transient
boundary. A separate burst during a delayed read verifies that ring drops are
counted and that the shell still accepts commands afterward.

The kernel shell depends on a bounded `ConsoleEventQueue` and `ConsoleWriter`,
not on the COM1 driver. COM1 remains the first input source; its IRQ4 handler
only fills the receive ring and counts drops. A normal-context decoder turns
serial bytes and ANSI escape sequences into shared key events. The reusable
line editor handles insertion, deletion, cursor movement, history, and redraw;
command parsing and file reads also run in the shell loop. `ConsoleWriter`
mirrors serial bytes to a framebuffer terminal with a visible cursor, basic
ANSI clearing and movement, and pixel-row scrolling. The QEMU serial tests
decode framebuffer screenshots to verify root-file text and the prompt, compare
screenshots across a bottom-row scroll, and assert that ordinary concurrent
serial/storage work loses no ring or event-queue input.

`src/kernel/vfs/Vfs.hy` defines the VFS boundary: filesystem drivers receive a
validated `BlockDevice` plus a bounded `Partition`, expose mount, file metadata,
lookup, and all-or-fail file reads, and are mounted as the single initial root.
The mount path clears an existing root before attempting a remount, so it never
leaves callers with a stale mounted-driver reference after a failed remount.

`src/kernel/vfs/Hyfs.hy` implements the first filesystem driver: read-only
HyFS v1. A HyFS partition has one logical-sector superblock, a CRC-32-protected
fixed-entry directory, and regular-file records with a full-content CRC-32.
The finalized on-disk layout and validation rules are in `docs/hyfs-v1.md`.
The driver accepts only 512 to 4096-byte logical sectors, a directory up to
64 KiB, and flat printable-ASCII paths such as
`/shell.hy`. It validates the superblock, directory allocation, reserved bytes,
file extents, duplicate names, and full file data before returning bytes to a
caller. `make test-hyfs1` constructs a complete in-memory HyFS 1 volume and checks
mounting, metadata, partial reads, EOF handling, VFS mounting, corrupted data,
corrupted metadata, and media I/O failure. It also verifies a checksum-pinned
v1 image fixture for later reader compatibility checks.

The mounted root is read-only. File reads stream over bounded sector buffers
and check the complete stored data CRC before returning bytes. The VFS exposes
root directory names and generation-checked persistent file handles. The
namespace normalizes nested paths. HyFS v1 stores only flat root files.

HyFS v2 is the default boot and removable-media format, with nested directories
and file metadata. `make iso` builds it, and the ordinary `make run`,
`make run-serial`, and `make run-nvme` targets boot it. The explicit
`iso-hyfs2`, `run-serial-hyfs2`, and `run-nvme-serial-hyfs2` are explicit
HyFS 2 targets. Run `make test-hyfs2` and
`make test-serial-ahci` (or `make test-serial-nvme`). The v2 shell can list
`/System`, `/System/Bin`, `/Applications`, `/Users`, `/Volumes`, and `/Temporary`; executable copies
are available in `/System/Bin`. The Hex Viewer executable is installed at
`/System/hexviewer.exec`. `stat /System` reports kind, size, object ID, and
timestamps when the image contains them. The kernel continues to mount v1
images. The versioned disk format and its recovery rules are in
`docs/hyfs-v2.md`.

Build and run the legacy format explicitly with `make iso-hyfs1`,
`make run-hyfs1`, `make run-serial-hyfs1`, `make run-nvme-hyfs1`, or
`make run-nvme-serial-hyfs1`. Its host compatibility suite is
`make test-hyfs1`; AHCI and NVMe boot checks are available through
`make test-hyfs1-boot-ahci` and `make test-hyfs1-boot-nvme`.

KMon searches `PATH=/System/Bin:/System:/` for bare executable names and adds
`.exec` automatically. Type `hexviewer` to run `/System/hexviewer.exec` or
`PATH=/System` to change KMon's search directories for the current session.
The normal userland shell starts with `PATH=/System/Bin`; type `path` to show
it or `path /System/Bin:/data/bin` to change it for that session. Explicit
`run /path/program.exec` still
works. Both forms pass arguments to `Main(string[] args)`:
`program /path/to/item -an --argument "two words"` and
`run /path/program.exec /path/to/item -an --argument` are valid. Single and
double quotes, plus backslash-escaped spaces, keep text in one argument.
Options are passed unchanged for each application to interpret; `-an` is one
argument and a long option begins with two ASCII hyphens (`--`). The shell
accepts up to 16 arguments within its 256-byte input line.
`inspector /System/Bin/inspector.exec` reports filesystem metadata and its AUEX
header; `inspector /System` lists that directory. Apps can pass an argument
path to the checked `Stat*`, `DirectoryCount`, `DirectoryName`, `OpenRead`,
and `OpenWrite` file APIs. `Files.ApiVersion()` reports the current AUEX file
API version, and bounded `ResultByte`/`ResultU32` calls expose read bytes.

`tools/hyfs2.py` provides offline file and directory operations for a v2 raw
image. For example, after `python3 tools/hyfs2.py create volume.img`, run
`python3 tools/hyfs2.py mkdir volume.img /Users`,
`python3 tools/hyfs2.py put volume.img note.txt /Users/note.txt`, and
`python3 tools/hyfs2.py ls volume.img /Users`. It also supports `cat`, `stat`,
`mv`, and `rm`. `python3 tools/hyfs2.py check volume.img` scans both generations
and reports invalid records and unreferenced nonzero blocks without writing.
Each edit publishes a new checked generation; the previous
generation can be used if an interrupted commit leaves the new one invalid.
The separate HyFS 2 data volume can be built with `make data-disk-hyfs2` and
booted with `make run-data-ahci` or `make run-data-nvme`. It appears
at `/data`; the boot image remains at `/` and removable media at `/usb`. The
data disk is a persistent raw image and is created only if absent, so normal
builds do not overwrite its contents. The default path is
`build/hyfs2-data.img`; `make clean` removes it. Set `HYFS2_DATA_DISK` to a
path outside `build/` to keep it across cleans. `make test-hyfs2-data-ahci` and
`make test-hyfs2-data-nvme` use disposable copies to check real block writes,
flushes, and readback after reboot. They also inject write errors; the AHCI
test injects a flush error. NVMe flush rejection is covered by host controller
tests because this QEMU NVMe setup does not forward blkdebug flush errors to
its namespace backend. The transactional HyFS 2 writer and VFS write calls
are enabled by default for the separate raw `/data` partition. The boot and
USB mounts stay read-only. `make test-stage6` covers host corruption,
interruption, capacity, and removal checks, then boots an AUEX writer on both
AHCI and NVMe to check persistence across reboots and live device removal.
The live removal check detaches the QEMU disk backend while the guest remains
running and verifies that `/data` reads fail without stopping the shell.

Before mounting storage, the kernel verifies the handoff's active four-level
page tables: the boot record must be mapped and virtual page zero must remain
unmapped. Shell commands mark and rewind a transient allocation region, so
their path strings, file buffers, and validation buffers do not consume memory
permanently. Freestanding managed objects, arrays, and strings carry a 16-byte
ownership header before the payload. `System.Kernel.Managed.Release(value)`
retires one allocation, rejects a duplicate release, and returns its backing
pages to the physical free list. Subsequent one-page allocations reuse released
pages. The command marker keeps shell temporaries out of that free list until
the command rewind completes. Boot checks cycle all three managed kinds,
release a multi-page array, and repeat map/unmap operations 64 times.

The live AHCI and NVMe transports route PCI MSI/MSI-X to vector `0x31`.
The APIC handler increments a completion counter; each controller waits for
that counter to change, checks completion status, and acknowledges the device
before reusing the command slot. Native waits sleep for interrupts and are
bounded by timer wakeups. Failed requests record timeout or device error,
controller reset, and exhausted retry states. The serial shell stays available
after failed storage operations. `make test-storage-failure-ahci` and
`make test-storage-failure-nvme` exercise the default HyFS 2 data-volume error
and recovery path. The explicit `make test-hyfs1-storage-failure-ahci` and
`make test-hyfs1-storage-failure-nvme` targets retain the legacy root-file read
failure check.
AHCI cause codes distinguish task readiness timeout (`1`), task/interrupt
error (`2`), short DMA (`3`), late task error (`4`), completion timeout (`5`),
command validation (`6`), and setup failure (`7`). NVMe codes distinguish
timeout (`1`), fatal controller status (`2`), completion error (`3`), and
setup failure (`4`).

## KernelBootInfo ABI

After `System.Kernel.Framebuffer.Initialize()` succeeds, the bootloader holds
this little-endian record. It passes the pointer to the raw kernel as its
argument and retains it in `R15` for freestanding allocation. The first page
also contains the GDT beginning at byte `512`; the IDT occupies the second
page. Loader-owned raw-image and stack fields begin at byte `1024`. The EFI
memory-map buffer is allocated as
`EfiLoaderData` and remains valid after `ExitBootServices`. The active paging
hierarchy has allocator-owned PML4, PDPT, PD, and PT pages. Its leaf entries
preserve the prior physical frames and attributes, so the existing mappings
remain valid until a kernel mapping policy changes them. This ABI is valid for
the four-level paging mode accepted by the current kernel handoff.

| Offset | Type | Value |
| --- | --- | --- |
| `0` | `uint32` | Magic: `AUBI` |
| `4` | `uint32` | ABI version: `7` |
| `8` | `uint64` | EFI memory-map address |
| `16` | `uint64` | Actual memory-map byte size |
| `24` | `uint64` | EFI descriptor size |
| `32` | `uint32` | EFI descriptor version |
| `36` | `uint32` | State flags: `1` memory map ready; `3` allocator ready; `15` paging hierarchy active; `31` null-page guard active; `63` heap ready; `127` framebuffer ready; `255` GDT active; `511` IDT active; `1023` interrupt controller ready; `2047` timer configured; `8191` PCI scanned; `16383` MMIO mapped; `32767` DMA ready; `131071` AHCI partition metadata ready; `262143` ready to enter the interrupt idle loop |
| `40` | `uint64` | First allocatable physical page |
| `48` | `uint64` | Exclusive upper bound of the physical-page range |
| `56` | `uint64` | Reserved and zeroed allocator metadata page |
| `64` | `uint64` | Active allocator-owned PML4 physical address |
| `72` | `uint64` | Most recently allocated and zeroed physical page; `0` until the first allocation |
| `80` | `uint64` | Heap base address |
| `88` | `uint64` | Next free, 16-byte aligned heap address |
| `96` | `uint64` | Exclusive end of the currently backed heap range |
| `104` | `uint64` | Most recent heap allocation address; `0` until the first allocation |
| `112` | `uint64` | GOP framebuffer base address |
| `120` | `uint64` | GOP framebuffer byte size |
| `128` | `uint32` | Horizontal resolution in pixels |
| `132` | `uint32` | Vertical resolution in pixels |
| `136` | `uint32` | Pixels per scan line |
| `140` | `uint32` | Raw EFI_GRAPHICS_PIXEL_FORMAT value |
| `144` | `uint32` | Framebuffer text cursor X in pixels |
| `148` | `uint32` | Framebuffer text cursor Y in pixels |
| `152` | `uint64` | GDT base address |
| `160` | `uint64` | IDT base address |
| `168` | `uint64` | Local APIC physical address |
| `176` | `uint64` | Monotonic local-APIC timer tick count; uncalibrated |
| `184` | `uint32` | Most recently dispatched IRQ or timer vector |
| `188` | `uint32` | Fatal CPU exception vector; `0` until an exception |
| `192` | `uint32` | APIC access mode: `0` xAPIC MMIO, `1` x2APIC MSR |
| `196` | `uint32` | Reserved |
| `200` | `uint32` | Number of present PCI functions discovered |
| `204` | `uint32` | First xHCI BDF (`bus << 8 | device << 3 | function`), or `0xffffffff` |
| `208` | `uint64` | xHCI memory BAR physical base; `0` when not mapped |
| `216` | `uint32` | First AHCI BDF, or `0xffffffff` |
| `220` | `uint32` | First NVMe BDF, or `0xffffffff` |
| `224` | `uint64` | AHCI memory BAR physical base; `0` when not mapped |
| `232` | `uint64` | NVMe memory BAR physical base; `0` when not mapped |
| `240` | `uint64` | xHCI 64 KiB high MMIO aperture, or `0` |
| `248` | `uint64` | AHCI 64 KiB high MMIO aperture, or `0` |
| `256` | `uint64` | NVMe 64 KiB high MMIO aperture, or `0` |
| `264` | `uint64` | Inclusive DMA physical-range floor |
| `272` | `uint64` | Next DMA allocation upper bound |
| `280` | `uint64` | Most recent DMA allocation physical base |
| `288` | `uint64` | Most recent DMA allocation byte size |
| `296` | `uint32` | Most recent DMA allocation page count |
| `300` | `uint32` | Reserved |
| `304` | `uint32` | Live block-controller kind: `1` for AHCI, `2` for NVMe |
| `308` | `uint32` | Reserved |
| `312` | `uint32` | Selected AHCI port number |
| `316` | `uint32` | Live block logical-sector size in bytes; currently `512` |
| `320` | `uint32` | MBR flags: bit 0 valid signature, bit 1 protective MBR |
| `324`–`347` | -- | Reserved |
| `348` | `uint32` | Nonzero emitted-kernel failure checkpoint; `0` after a successful handoff |
| `352` | `uint32` | GPT flags: bit 0 valid signature/header CRC, bit 1 primary entry-array CRC, bit 2 first valid entry recorded |
| `356` | `uint64` | Primary GPT entry-array LBA |
| `364` | `uint32` | GPT entry count |
| `368` | `uint32` | GPT entry size in bytes |
| `372` | `uint32` | Reserved |
| `376` | `uint64` | First present GPT partition start LBA; `0` when none exists |
| `384` | `uint64` | First present GPT partition block count; `0` when none exists |
| `392` | `uint32` | First present GPT partition index |
| `396` | `uint32` | Reserved |
| `400` | `uint64` | GPT first usable LBA |
| `408` | `uint64` | GPT last usable LBA |
| `416`–`436` | `uint32` | NVMe admin and I/O queue tail, head, and phase cursors |
| `444` | `uint32` | NVMe doorbell stride in bytes |
| `448` | `uint64` | Current NVMe read LBA |
| `456` | `uint32` | Remaining sectors in current NVMe read |
| `460` | `uint32` | Destination byte offset in GPT transfer buffer |
| `464` | `uint64` | Namespace 1 logical-sector count |
| `472` | `uint32` | Compiled Hylang entry completed (`1`) |
| `476` | `uint32` | Compiled Hylang entry status (`0` on success) |
| `480` | `uint64` | Zeroed page allocated by Hylang code |
| `488`–`492` | `uint32` | Object/array and literal-string runtime checks |
| `496` | `uint32` | Hylang NVMe sector read completed (`1`; zero for AHCI) |
| `500` | `uint32` | Hylang GPT reader completed (`1`) |
| `504`–`508` | `uint32` | GPT and block read diagnostic statuses |
| `1024` | `uint64` | Raw kernel entry address |
| `1032` | `uint64` | Raw kernel code byte count |
| `1040` | `uint64` | Raw image allocation base |
| `1048` | `uint64` | Dedicated kernel stack base |
| `1056` | `uint64` | Dedicated kernel stack top |
| `1064` | `uint64` | Previous bootloader stack pointer, used only if the kernel returns |
| `1072` | `uint32` | Root flags: bit 0 mounted, bit 1 `/hello.txt` verified, bit 2 `/readme.txt` verified |
| `1076` | `uint32` | VFS root mount status (`0` on success) |
| `1080` | `uint64` | `/hello.txt` byte length |
| `1088` | `uint64` | CRC-32 of bytes read from `/hello.txt` |
| `1096` | `uint64` | HyFS root first LBA |
| `1104` | `uint64` | HyFS root block count |
| `1112` | `uint32` | `/hello.txt` read status (`0` on success) |
| `1120` | `uint64` | `/readme.txt` byte length |
| `1128` | `uint64` | CRC-32 of bytes read from `/readme.txt` |
| `1136` | `uint32` | `/readme.txt` read status (`0` on success) |
| `1140` | `uint32` | COM1 flags: bit 0 initialized, bit 1 PIC IRQ4 receive enabled |
| `1144` | `uint32` | Number of submitted serial command lines |
| `1148` | `uint32` | COM1 IRQ4 delivery count |
| `1152` | `uint64` | Lowest allocation retained while the shell reclaims command temporaries |
| `1160` | `uint32` | Memory/runtime error code; zero means no recorded error |
| `1164` | `uint32` | Page-table validation error; zero means the audit passed |
| `1168` | `uint32` | COM1 receive-ring producer cursor |
| `1172` | `uint32` | COM1 receive-ring consumer cursor |
| `1176` | `uint32` | COM1 receive-ring dropped-byte count |
| `1184` | `uint64` | Head of the reusable physical-page free list; zero before the first page is returned |
| `1192` | `uint64` | Number of pages in that free list |
| `1200` | `uint32` | Kernel map/unmap and page-reuse self-test status; zero means it passed |
| `1204` | `uint32` | Managed allocation/release stress status; zero means it passed |
| `1208` | `uint64` | Active shell command allocation marker; zero outside a command |
| `1216` | `uint64` | Kernel-owned dynamic PML4 base; zero when all dynamic mappings have been released |
| `1224` | `uint64` | Storage MSI/MSI-X vector `0x31` delivery count |
| `1232` | `uint32` | Interrupt-backed storage kind: `1` AHCI, `2` NVMe, zero until configured |
| `1236` | `uint32` | Last storage failure cause; zero after a successful read |
| `1240` | `uint32` | Recovery state: `0` healthy, `1` timeout, `2` device error, `3` resetting, `4` retry exhausted |
| `1244` | `uint32` | PCI interrupt mode: `1` MSI, `2` MSI-X |
| `1248` | `uint64` | Optional mapped MSI-X table page |
| `1256` | `uint32` | Shared console event-queue dropped-event count |
| `1280`–`2303` | `uint8` | 1024-byte COM1 interrupt receive ring |
| `2304` | `uint64` | Reusable device vector `0x32` delivery count |
| `2312` | `uint32` | Registered reusable device vector; zero while unowned |
| `2316` | `uint32` | Reusable vector owner identifier |
| `2320` | `uint64` | Device interrupt status and W1C acknowledgement address |
| `2328` | `uint32` | Device interrupt pending-status mask |
| `2332` | `uint32` | Raw status observed by the device interrupt stub |
| `2336` | `uint32` | Device completions pending normal-context dispatch |
| `2340` | `uint32` | Device completions dropped by the normal-context event queue |
| `2344` | `uint64` | Calibrated TSC ticks per millisecond |
| `2352` | `uint32` | Clock calibration state: `1` ready, `2` failed |
| `2356` | `uint32` | Full xHCI BAR mapping retained for Stage 3 |
| `2360` | `uint32` | Stage 2 service self-test status; zero means it passed |
| `2368` | `uint64` | Kernel virtual address of the complete xHCI BAR mapping |
| `2376` | `uint64` | Complete xHCI BAR byte length |
| `2384` | `uint32` | xHCI lifecycle state (`10` keyboard ready, `20` storage ready) |
| `2388` | `uint32` | Last xHCI failure cause; zero while healthy |
| `2392` | `uint32` | Active xHCI root-port number |
| `2396` | `uint32` | Addressed xHCI slot identifier |
| `2400` | `uint64` | xHCI command completion count |
| `2408` | `uint64` | xHCI transfer completion count |
| `2416` | `uint64` | xHCI port-status-change count |
| `2424` | `uint64` | Boot-keyboard reports consumed in normal context |
| `2432` | `uint32` | Cumulative xHCI recovery count; consecutive failures are bounded separately |
| `2440` | `uint64` | Owned xHCI DMA allocation base |
| `2448` | `uint32` | xHCI PCI message mode: `1` MSI, `2` MSI-X |
| `2452` | `uint32` | Packed USB configuration, interface, and endpoint identifiers |
| `2456` | `uint32` | Number of xHCI scratchpad buffers initialized |
| `2460` | `uint32` | Keyboard layout identifier (`1` US) |
| `2464` | `uint64` | USB device removal count |
| `2472` | `uint32` | USB device kind (`1` keyboard, `2` mass storage) |
| `2476` | `uint32` | Packed storage configuration, interface, and bulk endpoint identifiers |
| `2480` | `uint32` | USB storage logical sector size |
| `2488` | `uint64` | USB storage logical sector count |
| `2496` | `uint64` | Successful USB block-read count |
| `2504` | `uint32` | Last SCSI sense key |
| `2512` | `uint32` | Removable-media GPT status |
| `2516` | `uint32` | Removable HyFS mount status |
| `2576` | `uint32` | Last AUEX process state (`2` exited, `3` faulted) |
| `2580` | `uint32` | Last AUEX exit code |
| `2584` | `uint32` | Last AUEX fault (`1` image, `2` instruction, `3` memory, `4` syscall, `5` limit, `6` arithmetic) |
| `2588` | `uint32` | Number of user-program launch attempts |
| `2592` | `uint64` | Instructions executed by the last AUEX process |
| `2600` | `uint32` | Fatal panic vector |
| `2604` | `uint32` | Nonzero when the CPU supplied an exception error code |
| `2608` | `uint64` | Fatal exception error code, or zero when absent |
| `2616` | `uint64` | Interrupted instruction pointer (`RIP`) |
| `2624` | `uint64` | Interrupted code segment (`CS`) |
| `2632` | `uint64` | Interrupted `RFLAGS` |
| `2640` | `uint64` | Stack pointer immediately before the CPU exception frame |
| `2648` | `uint64` | Captured `CR2` fault address |
| `2672` | `uint32` | Panic state: `1` rendering, `2` report complete and halted |
| `2688`–`3457` | `uint8` | Fixed allocation-free NUL-terminated ASCII panic report buffer |
| `3460` | `uint32` | Active AUEX file descriptors after the last wait |
| `3464` | `uint32` | Last foreground AUEX process ID |
| `3472` | `uint32` | Boot mode (`0` normal, `1` debug, `3` rescue) |
| `3476` | `uint32` | Recovery phase (`0` normal boot, `1` early recovery, `2` recovery shell) |
| `3608` | `uint64` | PhysicalPages ownership floor recorded before the first kernel allocation |

## UEFI Framebuffer offsets

| Offset | Type | Value |
| --- | --- | --- |
| `304` | -- | ProtocolsPerHandle |
| `312` | -- | LocateHandleBuffer |
| `320` | -- | LocateProtocol |
| `328` | -- | InstallMultipleProtocolInterfaces |
