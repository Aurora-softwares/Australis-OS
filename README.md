# Australis OS

<img src="assets/australis.icon.svg" width="200" />

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
`System.Kernel.Halt()`.
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

## KernelBootInfo ABI

After `System.Kernel.Framebuffer.Initialize()` succeeds, `RDI` points to this
little-endian, 152-byte record. The EFI memory-map buffer is allocated as
`EfiLoaderData` and remains valid after `ExitBootServices`. The active paging
hierarchy has allocator-owned PML4, PDPT, PD, and PT pages. Its leaf entries
preserve the prior physical frames and attributes, so the existing mappings
remain valid until a kernel mapping policy changes them. This ABI is valid for
the four-level paging mode accepted by the current kernel handoff.

| Offset | Type | Value |
| --- | --- | --- |
| `0` | `uint32` | Magic: `AUBI` |
| `4` | `uint32` | ABI version: `4` |
| `8` | `uint64` | EFI memory-map address |
| `16` | `uint64` | Actual memory-map byte size |
| `24` | `uint64` | EFI descriptor size |
| `32` | `uint32` | EFI descriptor version |
| `36` | `uint32` | State flags: `1` memory map ready; `3` allocator ready; `15` paging hierarchy active; `31` null-page guard active; `63` heap ready; `127` framebuffer ready |
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
| `140` | `uint32` | GOP pixel format: `0` RGB or `1` BGR |
| `144` | `uint32` | Framebuffer text cursor X in pixels |
| `148` | `uint32` | Framebuffer text cursor Y in pixels |
