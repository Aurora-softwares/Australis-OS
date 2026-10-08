# Australis OS

<img src="assets/australis.icon.svg" style="display: block;margin-left: auto; margin-right: auto; width: 30%;" />

Australis OS is a minimal x86_64 UEFI proof of concept authored in Hylang. It
boots directly from a UEFI ISO, writes boot status lines to the firmware console, and
then remains on screen:

```text
[BOOT] Hydrogen Bootloader
[BOOT] Loading EFI kernel...
[KERNEL] Australis kernel started.
[KERNEL] Capturing UEFI memory map.
[KERNEL] Leaving UEFI boot services.
```

This is deliberately a small compiler-target proof, not a kernel or general
UEFI runtime. The `uefi-x64` self-hosted Hylang target accepts a `Main` method with
`System.Console.WriteLine` ASCII string literals and emits the PE32+ EFI
application without C#, bflat, an assembler, or a linker.

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
`type = "efi"`; the kernel uses `type = "kernel"`. Hydrogen builds each as a separate
UEFI application and uses its `output` field to place it in the EFI
tree. You can invoke the compiler directly:

```bash
../Hylang-Compiler/build/self_hosting/hydrogen-stage1 build src/australlis.hyproj -o build/efi
```

`make build` runs that command. `make iso` builds and bundles these files:

```text
build/efi/EFI/BOOT/BOOTX64.EFI
build/efi/EFI/AUSTRALIS/KERNEL.EFI
build/efi/EFI/AUSTRALIS/SYSTEM.EFI
build/australis-hylang.iso
```

The bootloader reads `KERNEL.EFI` from the same FAT volume through UEFI boot
services and starts it with `LoadImage` and `StartImage`. `SYSTEM.EFI` is included
as a separate application, but the current boot sequence does not start it.
The ISO is hybrid: it
contains an El Torito UEFI boot entry for optical media and a GPT EFI System
Partition for direct writing to a USB drive or disk. It is not a virtual-disk
format.

Write the ISO byte-for-byte to the target drive; do not copy its files onto an
existing filesystem. This replaces that drive's contents. The target must boot
64-bit UEFI applications. Secure Boot must be disabled because the EFI
applications are not signed.

A standalone raw FAT image is also available through:

```bash
make image
```

at `build/australis-hylang-uefi.img`.

## Run

```bash
make run
```

This boots `build/australis-hylang.iso` in QEMU with OVMF as optical media. To
validate the same ISO as a hard disk, run:

```bash
make run-disk
```

For the post-handoff framebuffer console, run QEMU with OVMF and its standard
VGA device:

```bash
make run-gop
```

This opens QEMU's GTK window with an EFI Graphics Output Protocol (GOP)
framebuffer. VT-x/KVM is optional: without it QEMU uses software emulation,
which is slower but has the same GOP behavior.

Override the
default locations when needed:

```bash
make run HYDROGEN=/path/to/hydrogen-stage1 OVMF_CODE=/path/to/OVMF_CODE.fd
```

## Scope

The UEFI target supports `System.Uefi.ClearScreen()` before console output,
`System.Uefi.Await()` to wait for and consume one keyboard event, literal console
lines, starting one EFI application from the boot volume, and the kernel handoff
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
`System.Kernel.Interrupts.Enable()`, and `System.Kernel.Interrupts.Idle()`.
`KERNEL.EFI` captures a final UEFI memory map,
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

The interrupt sequence installs a ring-0 GDT, then an IDT with dedicated stubs
for CPU exceptions, legacy PIC vectors `0x20`–`0x2f`, and local-APIC timer
vector `0x30`. CPU exceptions save their vector in `KernelBootInfo` and halt.
The PIC is remapped and masked, so it cannot deliver device IRQs before a driver
has registered ownership. The local APIC is enabled in either xAPIC or x2APIC
mode; xAPIC receives an uncached identity mapping when its page is absent from
the cloned firmware hierarchy. The timer runs periodically and increments a raw
monotonic tick counter. Its rate is deliberately not treated as milliseconds or
seconds until the kernel calibrates it against a stable platform clock.

`Pci.Initialize()` scans every PCI bus, device, and function through
configuration mechanism #1 (`0xcf8`/`0xcfc`) and records the first xHCI, AHCI,
and NVMe controllers. `Mmio.Initialize()` reads their memory BARs and maps a
fixed 64 KiB high virtual aperture for each valid controller BAR. These leaves
are writable, non-cacheable (PCD/PWT), and non-executable. The mapping is for
controller registers; later storage and USB drivers must validate controller
specific register layouts and map any additional BAR extent they require.
`Dma.Initialize()` selects the largest usable conventional-memory interval below
4 GiB and reserves the literal DMA requests emitted in this kernel from its
high end. It removes that slice from the main physical allocator when both use
the same descriptor. `Dma.AllocatePages()` returns contiguous, zero-filled
physical pages from the reserved slice and records the latest allocation. This
bootstrap has no IOMMU programming yet, so device-specific DMA address-width
and cache coherency rules still belong to each driver.

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
entries. The first present GPT partition is published in `KernelBootInfo`; it
is metadata for the future VFS and does not mount a filesystem.

The paging-hierarchy copier targets the normal four-level x86_64 paging mode. It
detects an active five-level (LA57) hierarchy and halts before changing `CR3`.

The generated EFI applications use a zero image base and RIP-relative internal
references, so UEFI firmware can load them at an available address. They are
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

The current `uefi-x64` image builder emits only its fixed kernel intrinsic
calls from `Main`; it does not emit the general Hylang methods in this new
module. The resulting `KERNEL.EFI` therefore still cannot access USB hardware.
Before a keyboard, mouse, or flash drive can work after `ExitBootServices`, the
kernel needs freestanding PCI port I/O, MMIO mapping, DMA-safe allocation,
timeouts, xHCI command/event/transfer rings and port enumeration, USB control,
bulk and interrupt transfer scheduling, and input/block-device queues. The
mass-storage code can exercise a mocked block read, but it cannot yet read a
physical USB disk. The HID code decodes boot reports; it does not yet poll a
device or feed a console.

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
make test-ahci
make test-nvme
make test-nvme-controller
make test-nvme-boot
make test-partitions
make test-vfs
make test-hyfs
```

The constrained `uefi-x64` builder emits both controller paths when `Main`
calls `System.Kernel.Storage.Initialize()`. QEMU Q35/OVMF has exercised the
protective MBR, GPT header, and complete primary entry-array reads from the
generated ISO through both AHCI and NVMe. `make test-nvme-boot` repeats the NVMe
boot check and verifies the published partition. Physical controller validation
is still required; the live image has not mounted a VFS root yet.

`src/kernel/vfs/Vfs.hy` defines the VFS boundary: filesystem drivers receive a
validated `BlockDevice` plus a bounded `Partition`, expose mount, file metadata,
lookup, and all-or-fail file reads, and are mounted as the single initial root.
The mount path clears an existing root before attempting a remount, so it never
leaves callers with a stale mounted-driver reference after a failed remount.

`src/kernel/vfs/Hyfs.hy` implements the first filesystem driver: read-only
HyFS v1. A HyFS partition has one logical-sector superblock, a CRC-32-protected
fixed-entry directory, and regular-file records with a full-content CRC-32.
The driver accepts only 512 to 4096-byte logical sectors, a directory up to
64 KiB, files up to 1 MiB, and flat printable-ASCII paths such as
`/shell.hy`. It validates the superblock, directory allocation, reserved bytes,
file extents, duplicate names, and full file data before returning bytes to a
caller. `make test-hyfs` constructs a complete in-memory HyFS volume and checks
mounting, metadata, partial reads, EOF handling, VFS mounting, corrupted data,
corrupted metadata, and media I/O failure.

This driver is compiled into the kernel project, but the current `uefi-x64`
image builder only emits its fixed boot intrinsics. `KERNEL.EFI` therefore does
not yet instantiate the Hylang VFS or mount HyFS from its live AHCI transport.
Wiring that general freestanding method code and selecting a HyFS GPT partition
are the next integration step. FAT/FAT32 remains a later compatibility driver.

## KernelBootInfo ABI

After `System.Kernel.Framebuffer.Initialize()` succeeds, `RDI` points to this
little-endian record, currently defined through byte `415`. The EFI memory-map buffer is allocated as
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

## UEFI Framebuffer offsets

| Offset | Type | Value |
| --- | --- | --- |
| `304` | -- | ProtocolsPerHandle |
| `312` | -- | LocateHandleBuffer |
| `320` | -- | LocateProtocol |
| `328` | -- | InstallMultipleProtocolInterfaces |
