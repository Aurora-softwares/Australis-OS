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
make iso
```

This compiles the bootloader and kernel UEFI applications and produces:

```text
build/efi/EFI/BOOT/BOOTX64.EFI
build/efi/EFI/AUSTRALIS/KERNEL.EFI
build/australis-hylang.iso
```

The bootloader reads `KERNEL.EFI` from the same FAT volume through UEFI boot
services and starts it with `LoadImage` and `StartImage`. The ISO is hybrid: it
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

The UEFI target supports literal console lines, starting one EFI application
from the boot volume, and the kernel handoff sequence:
`System.Uefi.ExitBootServices()`, `System.Kernel.MemoryMap.Initialize()`,
`System.Kernel.Memory.Initialize()`, `System.Kernel.VirtualMemory.Initialize()`,
and `System.Kernel.Halt()`. `KERNEL.EFI` captures a final UEFI memory map,
reserves space for 64 additional memory descriptors, then retries the
`GetMemoryMap`/`ExitBootServices` pair up to eight times if firmware changes the
map key. It initializes its physical-page allocator after the successful
handoff. The allocator selects the largest
`EfiConventionalMemory` region, reserves and clears its first 4 KiB page for
metadata, then publishes the remaining page range. Virtual-memory initialization
clones the active PML4 into an allocator page and loads that kernel-owned root
into `CR3`, retaining its present mappings. The `KernelBootInfo` record and its
`RDI` pointer survive the handoff. Console output stops at the handoff because
it depends on firmware services. Replacing inherited lower-level tables, a page
allocation API, framebuffer output, and drivers follow next.

The generated EFI applications use a zero image base and RIP-relative internal
references, so UEFI firmware can load them at an available address. They are
tested as both an El Torito ISO and a hard disk image under OVMF. Physical
hardware validation still requires booting a test USB or disk on each firmware
family that Australis intends to support.

## KernelBootInfo ABI

After `System.Kernel.VirtualMemory.Initialize()` succeeds, `RDI` points to this
little-endian, 72-byte record. The EFI memory-map buffer is allocated as
`EfiLoaderData` and remains valid after `ExitBootServices`. The active PML4 is
a kernel-owned copy of the prior root, so the existing mappings remain valid
while later work replaces the inherited lower-level table pages.

| Offset | Type | Value |
| --- | --- | --- |
| `0` | `uint32` | Magic: `AUBI` |
| `4` | `uint32` | ABI version: `1` |
| `8` | `uint64` | EFI memory-map address |
| `16` | `uint64` | Actual memory-map byte size |
| `24` | `uint64` | EFI descriptor size |
| `32` | `uint32` | EFI descriptor version |
| `36` | `uint32` | State flags: `1` memory map ready; `3` allocator ready; `7` PML4 active |
| `40` | `uint64` | First allocatable physical page |
| `48` | `uint64` | Exclusive upper bound of the physical-page range |
| `56` | `uint64` | Reserved and zeroed allocator metadata page |
| `64` | `uint64` | Active kernel-owned PML4 physical address |
