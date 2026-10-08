# Australis OS Active Plan

This plan records the current, Hydrogen-first path. It is a companion to the
Australis documentation and the Hylang compiler's OS roadmap.

## Current capability: v0 proof of concept

Australis currently proves one narrow but important path end to end:

- `src/bootloader/program.hy` is compiled by the retained self-hosted
  `hydrogen-stage1` compiler.
- `--target uefi-x64` emits a PE32+ x86-64 EFI application with an EFI entry
  point, UTF-16 output, and a direct UEFI text-console call.
- `mtools` and `xorriso` package that application into either a FAT disk image
  or an El Torito UEFI ISO. They do not compile Hydrogen.
- QEMU with OVMF boots the ISO, then the bootloader loads and starts
  `EFI/AUSTRALIS/KERNEL.EFI` from the same FAT volume.

The current EFI target is intentionally constrained. It supports firmware
console calls before `ExitBootServices`, then transfers to a freestanding kernel
handoff with memory-map, physical-page, paging-policy, and bootstrap-heap
support. Arbitrary Hydrogen method compilation, a general runtime library, a
command shell, and a raw kernel-image format remain later work.

## Completed

- [x] Self-hosted compiler emits a PE32+ x86-64 UEFI image.
- [x] UEFI entry-point ABI and firmware console function-pointer call.
- [x] UTF-16 encoding for the firmware console string.
- [x] Load a kernel EFI application through UEFI file, image, and boot services.
- [x] `src/bootloader/program.hy` is the current boot source; the old C# source
  was removed.
- [x] `make build`, `make image`, `make iso`, and `make run` use the
  self-hosted compiler plus packaging tools.
- [x] Boot the generated ISO in QEMU/OVMF and verify the text output.
- [x] Capture a final UEFI memory map, call `ExitBootServices`, then disable
  interrupts and idle in the kernel.

## Next: `Hydrogen.Uefi` library

Goal: turn the one-purpose output path into a small, explicit firmware library
that Hydrogen programs can use without embedding protocol offsets in every
program.

- [ ] Define UEFI-compatible data layouts, pointers, status values, and calling
  conventions in the compiler/language surface.
- [ ] Add `Hydrogen.Uefi.Console.Write`, `WriteLine`, and `Clear`.
- [ ] Add keyboard input through the simple text-input protocol.
- [ ] Add basic boot-service and memory-map wrappers.
- [ ] Add tests that compile and boot each wrapper example in QEMU/OVMF.
- [ ] Add graphics-output support after the text and input APIs are stable.

## Then: firmware-hosted command shell

Goal: make Australis interactive while UEFI boot services are still available.

- [ ] Read a line from the keyboard and render a prompt.
- [ ] Add a bounded input buffer and editing for Enter and Backspace.
- [ ] Implement `help`, `clear`, `echo`, `version`, and diagnostic commands.
- [ ] Add a panic/reporting path that leaves errors visible in QEMU.
- [ ] Keep all shell source and its supporting library in Hydrogen.

This phase is firmware-hosted software, not an independent kernel: UEFI still
owns memory, drivers, and platform services.

## Kernel transition

Goal: make the boundaries explicit before calling `ExitBootServices`.

- [x] Preserve the UEFI memory map in `KernelBootInfo` and pass its pointer in
  `RDI` to post-handoff Hydrogen code.
- [x] Call `ExitBootServices` successfully and continue execution in an
  interrupt-disabled halt loop.
- [x] Retry the final `GetMemoryMap`/`ExitBootServices` pair with a fixed
  descriptor reserve when the firmware updates its map key.
- [x] Emit position-independent UEFI PE32+ images with a zero image base.
- [x] Initialize a bootstrap physical-page range from the largest
  `EfiConventionalMemory` descriptor.
- [x] Clone every present PML4, PDPT, PD, and PT page into allocator-owned pages
  and activate the resulting hierarchy through `CR3` while retaining current
  leaf mappings.
- [x] Keep virtual page zero unmapped, splitting only the required large leaf.
- [x] Expose zero-filled 4 KiB page allocation through `KernelBootInfo`.
- [x] Build a page-backed, 16-byte aligned bump heap over that allocator.
- [x] Capture GOP framebuffer metadata before `ExitBootServices`, then clear and
  render literal text through direct pixel writes without firmware services.
- [x] Install a ring-0 GDT and IDT, capture fatal exception vectors, remap and
  mask the legacy PIC, enable the local APIC, and dispatch periodic timer IRQs
  into an uncalibrated monotonic tick counter.
- [x] Enumerate PCI functions through configuration-space port I/O, retain the
  first xHCI, AHCI, and NVMe function addresses, and map fixed uncached high
  MMIO register apertures for valid controller BARs.
- [x] Allocate contiguous, zero-filled DMA pages below 4 GiB and reserve their
  requested slice from the primary physical allocator when both overlap.
- [x] Define a synchronous, all-or-nothing block-device contract with checked
  geometry, overflow-safe range validation, and explicit error status.
- [x] Add host-tested AHCI SATA port discovery, bounded engine sequencing,
  IDENTIFY parsing, and IDENTIFY/READ DMA EXT command layouts.
- [x] Add host-tested NVMe queue command layouts, namespace geometry parsing,
  and one-page PRP read bounds.
- [x] Add host-tested protective-MBR and CRC-checked GPT header and entry-array
  parsing.
- [x] Emit and execute bounded polling AHCI reads in `KERNEL.EFI` for the MBR,
  GPT header, and primary GPT entry array; validate both GPT CRCs and publish
  the first present partition.
- [x] Define and host-test a VFS root-mount interface over a bounded partition.
- [x] Implement and host-test a read-only HyFS v1 driver with superblock,
  directory, and complete-file CRC validation.
- [x] Emit and boot NVMe admin/I/O queues, Identify, bounded polling reads,
  and the shared CRC-checked GPT discovery path under QEMU Q35/OVMF.
- [ ] Connect live AHCI and NVMe block reads to VFS and mount a HyFS root.
- [ ] Establish keyboard and storage drivers.
- [x] Add host-tested Hylang USB protocol code for PCI xHCI discovery,
  controller stop/reset, descriptor selection, MSC BOT reads via a mock
  transport, and boot HID reports with a basic US keymap.
- [ ] Add driver-facing BAR sizing, dynamic MMIO mapping, IOMMU setup where
  present, timer calibration, and cache/DMA synchronization rules.
- [ ] Complete xHCI rings, port enumeration, control/bulk/interrupt transfers,
  then connect MSC and HID to the kernel's block and input queues.
- [ ] Define a kernel/runtime boundary, then introduce userland and syscalls as
  the system matures.

At that point Australis becomes independent of the firmware runtime rather than
an EFI application that uses it. The sequence matters: build and test the
compiler/library contracts first, then depend on them for the shell and kernel.

## Bootstrap note

Once a verified `hydrogen-stage1` binary exists, supported compiler and OS
builds do not require C++ or a host C compiler. A clean source-only compiler
checkout still needs a trusted Hydrogen seed or the initial SDK bootstrap route.
