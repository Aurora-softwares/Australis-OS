# Australis OS Active Plan

This plan records the current, Hydrogen-first path. It is a companion to the
Australis documentation and the Hylang compiler's OS roadmap.

## Current capability: freestanding kernel and serial shell

Australis currently proves one narrow but important path end to end:

- `src/bootloader/program.hy` is compiled by the retained self-hosted
  `hydrogen-stage1` compiler.
- `--target uefi-x64` emits a PE32+ x86-64 EFI application with an EFI entry
  point, UTF-16 output, and a direct UEFI text-console call.
- `mtools` and `xorriso` package that application into either a FAT disk image
  or an El Torito UEFI ISO. They do not compile Hydrogen.
- QEMU with OVMF boots the ISO. The bootloader loads and validates
  `EFI/AUSTRALIS/KERNEL.BIN`, ends boot services, switches stack, and enters
  the raw kernel code.

The EFI target supports firmware console calls before `ExitBootServices`, then
transfers to a compiled `KernelMain.Run(long bootInfo)` method graph. That graph
uses kernel-owned physical pages for arrays, objects, and literal strings. It
reinitializes AHCI or NVMe through Hylang MMIO/DMA adapters, reads sectors
through the common block interface, validates GPT with the Hylang reader, and
mounts the HyFS partition by its full GPT type GUID. It reads files through the
VFS on both AHCI and NVMe, including a file spanning multiple sectors. Its
COM1 shell uses PIC IRQ4 to fill a bounded receive ring and runs `help`,
`echo`, `ls`, `cat`, and `version` against the mounted root. Each shell
command reclaims its temporary allocations after completing.
Only the bootloader remains a UEFI PE image in this path. The kernel is a
position-independent `AUKR` binary and calls no firmware service. Reclaimable
memory, file handles, process loading, and user programs remain later work.

## Full subsystem completion gate

The checked items below describe working bootstrap milestones. They do not
mean the subsystem is complete. A completed subsystem must run in the
freestanding kernel, expose a reusable interface, handle bounded failures and
recovery, and have host tests plus a QEMU/OVMF integration test. Physical PC
coverage needs separate hardware validation.

| Subsystem | Current gap before completion |
| --- | --- |
| Compiler and runtime | Reachable methods, objects, arrays, strings, direct memory access, and byte port I/O run after UEFI handoff. Allocation failures are recorded before trapping, and the shell reclaims a scoped transient tail. Add reusable boot-information types, general allocation/free, and bounded recovery. |
| Physical and virtual memory | The active PML4 is audited before driver startup: the boot record is mapped and virtual page zero is unmapped. A kernel page pool reuses explicitly returned pages, and a 4 KiB map/unmap interface uses a free PML4 slot and invalidates the local TLB. Add memory-descriptor ownership, allocation for managed objects, page-table reclamation, cache policy, and allocator stress tests. |
| Exceptions, interrupts, and timer | Exception vectors record state and the generated handlers preserve all general registers. COM1 uses a PIC IRQ4 receive ring. Add IRQ registration, calibrated timeouts, and device interrupts for storage and USB. |
| PCI, MMIO, and DMA | Size BARs, map complete register ranges dynamically, define cache and DMA synchronization rules, and handle platforms with an IOMMU or explicitly reject unsupported configurations. |
| AHCI and NVMe | Reusable polling controllers now read live QEMU devices through the common block interface. Add enumeration beyond the selected device, timeout recovery, real flush/write behavior, and broader hardware validation. |
| Partition discovery | The Hylang GPT reader now runs on live AHCI and NVMe, checks CRCs with backup-header recovery, and selects HyFS by full type GUID. Add partition selection by unique identity and a live damaged-primary integration test. |
| VFS and HyFS | A read-only HyFS root now mounts on live AHCI/NVMe; verified reads cross sector boundaries and the shell lists root names. Add persistent file handles and nested directory traversal, then exercise live corruption and I/O failures. |
| Interactive console | A COM1 shell accepts bounded, editable lines from a 1024-byte IRQ-fed receive ring and reads the real mounted root on AHCI/NVMe. Add terminal control and scheduled input dispatch. |
| USB | Install xHCI rings and contexts, enumerate ports/devices, perform control/bulk/interrupt transfers, and connect MSC/HID to block/input services. |

The compiler/runtime row gates live use of the host-tested Hydrogen drivers.
The immediate engineering sequence is compiler/runtime ABI, memory ownership,
live block and GPT adapters, live VFS file operations, interrupt-driven storage/input,
then xHCI enumeration and transfers. Each row stays open until its stated
integration path exists.

## Completed

- [x] Self-hosted compiler emits a PE32+ x86-64 UEFI image.
- [x] UEFI entry-point ABI and firmware console function-pointer call.
- [x] UTF-16 encoding for the firmware console string.
- [x] Load and validate a separate raw kernel binary, capture the final memory
  map, leave boot services, allocate a kernel stack, and jump to its entry.
- [x] `src/bootloader/program.hy` is the current boot source; the old C# source
  was removed.
- [x] `make build`, `make image`, `make iso`, and `make run` use the
  self-hosted compiler plus packaging tools.
- [x] Boot the generated ISO in QEMU/OVMF and verify the text output.
- [x] Capture a final UEFI memory map, call `ExitBootServices`, then enter the
  raw kernel on its own stack; the kernel enables interrupts and idles.
- [x] Bring up a post-handoff COM1 console and run a kernel shell with bounded
  editing and `help`, `echo`, `ls`, `cat`, and `version` on AHCI and NVMe roots.

## Next kernel milestones

- [ ] Give temporary allocations a reclaimable lifetime, including repeated
  shell file reads.
- [ ] Add persistent VFS file handles and nested directory traversal.
- [ ] Add a program format, loader, and a first user program.
- [ ] Add input queues and device IRQ handling beyond the timer.

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
- [x] Add a reusable host-tested Hydrogen AHCI polling controller with
  page-bounded multi-sector reads, transfer-byte verification, and timeout
  failure handling behind the common block transport.
- [x] Add host-tested NVMe queue command layouts, namespace geometry parsing,
  and one-page PRP read bounds.
- [x] Add host-tested protective-MBR and CRC-checked GPT header and entry-array
  parsing.
- [x] Add a host-tested block-level GPT reader with streamed entry-array CRCs,
  disk-bound checks, and backup-header recovery.
- [x] Emit and execute bounded polling AHCI reads in the bootloader for the MBR,
  GPT header, and primary GPT entry array; validate both GPT CRCs and publish
  the first present partition.
- [x] Define and host-test a VFS root-mount interface over a bounded partition.
- [x] Implement and host-test a read-only HyFS v1 driver with superblock,
  directory, and complete-file CRC validation.
- [x] Emit and boot NVMe admin/I/O queues, Identify, bounded polling reads,
  and the shared CRC-checked GPT discovery path under QEMU Q35/OVMF.
- [x] Compile a reachable Hylang method graph for post-handoff execution with
  kernel-owned object, array, and literal-string allocation.
- [x] Connect the reusable Hylang AHCI and NVMe controllers to live MMIO/DMA
  adapters, read through `BlockDevice`, and verify GPT with `GptDisk` under
  QEMU/OVMF for both controller types.
- [x] Connect live AHCI and NVMe block reads to VFS, select the HyFS GPT type,
  mount the root, and verify single- and multi-sector file reads in QEMU/OVMF.
- [x] Run an interactive serial shell with root listing and file display in
  both AHCI and NVMe QEMU boots.
- [x] Audit the live page tables, retain a protected persistent allocation
  floor for the shell, and deliver COM1 input through a register-preserving
  PIC IRQ4 handler on both QEMU storage paths.
- [x] Add a reusable zeroed physical-page pool with duplicate-free protection,
  and map, translate, unmap, and reuse a page through a kernel-owned 4 KiB
  PML4 slot on the live AHCI/NVMe paths.
- [ ] Add VFS file handles and nested directory traversal, then test live corrupt-media
  and I/O failure paths.
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

The running kernel is already independent of firmware boot services after the
handoff. These remaining stages turn its bootstrap into a fuller OS. The
sequence matters: extend and test compiler/runtime contracts before moving
more subsystem code into the live kernel.

## Bootstrap note

Once a verified `hydrogen-stage1` binary exists, supported compiler and OS
builds do not require C++ or a host C compiler. A clean source-only compiler
checkout still needs a trusted Hydrogen seed or the initial SDK bootstrap route.
