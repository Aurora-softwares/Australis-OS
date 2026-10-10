# Australis OS

<img src="assets/australis.icon.svg" style="display: block;margin-left: auto; margin-right: auto; width: 30%;" />

Australis OS is an x86_64 freestanding kernel booted from a UEFI ISO. The
Hylang bootloader loads the separate raw `KERNEL.BIN`, captures the final
memory map, leaves boot services, prepares paging and interrupts, switches to
a kernel stack, and calls the kernel entry. The kernel uses no firmware API.
The firmware console shows the early handoff:

```text
[BOOT] Australis bootloader started.
[BOOT] Loading raw kernel image.
[BOOT] Preparing kernel handoff.
[BOOT] Leaving UEFI boot services.
```

The self-hosted compiler emits the bootloader as PE32+ and the kernel as an
`AUKR` raw image without C#, bflat, an assembler, or a linker. The kernel
executes a compiled `KernelMain.Run(long bootInfo)` method graph after the
bootloader calls `ExitBootServices`. It uses
freestanding memory intrinsics, page-backed object/array allocation, and live
Hylang AHCI or NVMe drivers to validate GPT, mount a read-only HyFS root, and
read files through the VFS. A COM1 interrupt receive ring runs the initial user
shell registry with `help`, `echo`, `ls`, `cat`, `devices`, `mounts`, `pwd`,
`run`, `ps`, and `version`. The console supervisor owns devices and privileged
services; checked AUEX programs use terminal and file-descriptor syscalls.
The bootstrap still has
limits described below; it is not yet a general-purpose OS.

## Requirements

- A built self-hosted Hylang compiler
  (`../Hylang-Compiler/build/self_hosting/hydrogen-stage1` by default), or set
  `HYDROGEN=/path/to/hydrogen-stage1`.
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

`src/australlis.hyproj` is a Hydrogen `os` project referencing the bootloader,
kernel, and system projects. The bootloader and system projects use
`type = "efi"`; the kernel uses `type = "kernel"`. Hydrogen builds the
bootloader and system projects as UEFI applications, and the kernel as a raw
binary. Each manifest's `output` field places the artifact in the EFI tree.
You can invoke the compiler directly:

```bash
../Hylang-Compiler/build/self_hosting/hydrogen-stage1 build src/australlis.hyproj -o build/efi
```

`make build` runs that command. `make iso` builds and bundles these files:

```text
build/efi/EFI/BOOT/BOOTX64.EFI
build/efi/EFI/AUSTRALIS/KERNEL.BIN
build/efi/EFI/AUSTRALIS/SYSTEM.EFI
build/boot/root.hyfs.img
build/australis-hylang.iso
```

The bootloader reads `KERNEL.BIN` from the same FAT volume, validates its
`AUKR` header and exact size, and places it in executable loader memory before
the final memory-map capture. After `ExitBootServices`, it switches to a
dedicated 64 KiB kernel stack and enters the raw code. `SYSTEM.EFI` is included
as a separate application, but the current boot sequence does not start it.
The raw header is 16 bytes: `AUKR`, version `1`, code length, and entry offset
`16`, all little endian. The code is position independent.
The ISO is hybrid: it contains an El Torito UEFI boot entry for optical media,
a GPT EFI System Partition, and a 4 MiB read-only HyFS partition for the kernel
root. Hydrogen compiles the projects in `applications/Applications.hyproj`
directly to `.exec` files in the generated root tree, then
`tools/make_hyfs_image.py` packs it into that partition. Its GPT type GUID is
`9f5eb82e-692e-5a8f-b968-adaaa349dd93`.
The ISO can also be written directly to a USB drive or disk. It is not a
virtual-disk format.

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

This boots `build/australis-hylang.iso` in QEMU with OVMF as optical media and
attaches the same image as an AHCI disk for the kernel's live HyFS root. The
QEMU window sends keyboard input through the emulated xHCI USB keyboard. To
boot directly from the image's GPT EFI partition on AHCI, run:

```bash
make run-disk
```

`make run-disk` also attaches the xHCI USB keyboard. For the NVMe storage path,
run `make run-nvme`; it provides the same graphical terminal and keyboard. The
ISO remains optical boot media while the same image is attached as an NVMe
namespace.

Click the QEMU display once so it captures keyboard input. QEMU's default key
combination for releasing the pointer and keyboard is Ctrl+Alt+G.

For the interactive kernel console in the terminal, run:

```bash
make run-serial
# or: make run-serial-nvme
```

To attach the ISO as a second read-only USB mass-storage volume and use COM1
for the shell, run `make run-usb-storage` (AHCI boot root) or
`make run-usb-storage-nvme`. The removable HyFS volume appears at `/usb`; use
`devices`, `mounts`, `ls /usb`, and `cat /usb/hello.txt` to inspect it.

Wait for `australis> `, then type `help`. `ls` lists the flat HyFS root and
`cat /hello.txt` reads a file from the mounted AHCI or NVMe device. The console
echoes input and accepts Enter, Backspace/Delete, arrow keys, Home/End,
Ctrl-A/Ctrl-E, Ctrl-C, Ctrl-L, Ctrl-U, and eight entries of command history.
Its line buffer holds 256 bytes. Namespace paths canonicalize repeated `/`, `.`,
and `..`, and cross the removable mount at `/usb`; HyFS v1 components remain
limited to its flat 32-byte names. `cat` accepts files up to 64 KiB. The UART
uses COM1 at 115200 baud, 8 data bits, no parity, and one stop
bit. Its PIC IRQ4 handler copies received data into a 1024-byte kernel ring,
then the shell drains that ring after it wakes. A full ring drops new input and
records the drop count in `KernelBootInfo`.

Run the included user program from either COM1 or the framebuffer terminal:

```text
australis> run /user-demo.exec
Starting user program.
user> hello
input: hello
file: Hello from Australis HyFS.
User program exited cleanly.
```

`run /user-fault.exec` exercises the protected-write failure path and returns
to the shell. `ps` reports the most recent program state.

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
make run HYDROGEN=/path/to/hydrogen-stage1 OVMF_CODE=/path/to/OVMF_CODE.fd
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
framebuffer before halting. The `panic-test` shell command deliberately reads
the protected null page so this path can be exercised under QEMU.
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

The generated EFI bootloader and system applications use a zero image base and
RIP-relative internal references, so firmware can load them at an available address. They are
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

The kernel now owns one live xHCI controller and one root-port device. It
configures MSI or MSI-X vector `0x32`, initializes DCBAA and scratchpads plus
command, event, EP0, interrupt, and bulk rings, then enumerates either a boot
keyboard or a USB mass-storage device. Keyboard reports enter the same
normal-context console path as COM1. USB storage uses BOT and SCSI READ CAPACITY,
REQUEST SENSE, and READ(10), exposes the common block-device interface, and can
mount a second read-only HyFS volume at `/usb`. Disconnects, stalls, transfer
failures, and unit-attention responses have bounded recovery while COM1 and the
boot root remain available. Multiple simultaneous devices, hubs, non-US
layouts, and writable removable media remain later work.

The live keyboard matrix is `make test-stage3`; the AHCI and NVMe USB-storage
matrix is `make test-stage4`.

## AUEX `.exec` user programs

AUEX v1 is Australis's first user program format. Files use the `.exec`
extension defined in `src/system/README.md`; `AUEX` remains the internal format
magic and ABI name. Its 32-byte little-endian
header contains `AUEX`, version and header size, code length, initialized data
length, data capacity, entry offset, and separate CRC-32 values for code and
data. The image exposes a read-only code region at `0x400000` and a bounded
read/write data region at `0x500000`.

The interpreter provides exit, terminal read/write, read-only open/read/close,
checked byte stores, branches, and cooperative yield operations. Descriptors
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

This is software enforced isolation for the AUEX instruction set. Native x86-64
ring-3 execution, hardware page-table privilege separation, and preemptive
threads are later work. The current boundary establishes the executable,
terminal, descriptor, failure, and scheduling contracts before that transition.

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
make test-terminal
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
The driver accepts only 512 to 4096-byte logical sectors, a directory up to
64 KiB, and flat printable-ASCII paths such as
`/shell.hy`. It validates the superblock, directory allocation, reserved bytes,
file extents, duplicate names, and full file data before returning bytes to a
caller. `make test-hyfs` constructs a complete in-memory HyFS volume and checks
mounting, metadata, partial reads, EOF handling, VFS mounting, corrupted data,
corrupted metadata, and media I/O failure.

The mounted root is read-only. File reads stream over bounded sector buffers
and check the complete stored data CRC before returning bytes. The VFS exposes
root directory names to the serial shell. Persistent file handles, nested
directory traversal, and executable loading remain future work.

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
after a failed file read. `make test-storage-failure-ahci` and
`make test-storage-failure-nvme` inject real QEMU block I/O errors after boot.
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
| `2584` | `uint32` | Last AUEX fault (`3` protected memory access) |
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

## UEFI Framebuffer offsets

| Offset | Type | Value |
| --- | --- | --- |
| `304` | -- | ProtocolsPerHandle |
| `312` | -- | LocateHandleBuffer |
| `320` | -- | LocateProtocol |
| `328` | -- | InstallMultipleProtocolInterfaces |
