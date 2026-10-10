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
COM1 shell uses PIC IRQ4 to fill a bounded receive ring and runs the user shell
registry against the mounted namespace. Each shell command and AUEX process
reclaims its temporary allocations after completing.
Only the bootloader remains a UEFI PE image in this path. The kernel is a
position-independent `AUKR` binary and calls no firmware service. Individual
managed allocations can be released. Persistent file descriptors, AUEX process
loading, bounded scheduling, and checked user code/data address spaces are live.

## Full subsystem completion gate

The checked items below describe working bootstrap milestones. They do not
mean the subsystem is complete. A completed subsystem must run in the
freestanding kernel, expose a reusable interface, handle bounded failures and
recovery, and have host tests plus a QEMU/OVMF integration test. Physical PC
coverage needs separate hardware validation.

| Subsystem | Current gap before completion |
| --- | --- |
| Compiler and runtime | Objects, arrays, and strings now carry ownership metadata and support explicit individual release; shell temporaries still use a command marker. Add reusable boot-information types and automatic lifetime management. |
| Physical and virtual memory | The active PML4 is audited; page tables are reclaimed after unmap, released pages are reused, and live stress checks repeat mapping and managed release. Add memory-descriptor ownership and broader cache policy. |
| Exceptions, interrupts, and timer | Exception vectors record state, COM1 uses PIC IRQ4, storage uses APIC vector `0x31`, and xHCI uses deferred vector `0x32` events with calibrated deadlines. Add vector allocation beyond the current fixed assignments. |
| PCI, MMIO, and DMA | BARs are sized and fully mapped, xHCI DMA ownership is explicit, and unsupported IOMMU translation is rejected. Add translated DMA support and broader cache-policy validation. |
| AHCI and NVMe | Controllers use MSI/MSI-X completion waits with one reset/retry and failure diagnostics; QEMU exercises delayed and failed reads. Add enumeration beyond the selected device, real flush/write behavior, and broader hardware validation. |
| Partition discovery | The Hylang GPT reader now runs on live AHCI and NVMe, checks CRCs with backup-header recovery, and selects HyFS by full type GUID. Add partition selection by unique identity and a live damaged-primary integration test. |
| VFS and HyFS | Persistent generation-checked handles and canonical namespace traversal cover `/` and `/usb`; HyFS v1 itself remains flat. Add an on-disk directory format and live corruption tests. |
| Interactive console | COM1 and USB HID share line editing; AUEX fd 0/1/2 uses the same canonical read and mirrored write semantics. Add layout selection, pipelines, and background jobs. |
| USB | One live xHCI root device supports either a US keyboard or MSC bulk storage with bounded hotplug recovery. Add hubs and multiple simultaneous devices. |

The next engineering sequence is preemptive native processes, a richer on-disk
filesystem, and multi-device USB topology. Each row stays open until its stated
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

## Roadmap: interactive terminal and USB

Work through these milestones in order. Each has a runnable exit check, so the
serial shell remains usable while new input and storage paths are brought up.

### 1. Shared terminal and input (complete)

- [x] Separate the shell from COM1 through input and output interfaces. Keep
  COM1's bounded IRQ-fed ring, count dropped bytes, and execute commands in
  normal kernel context. QEMU covers command editing and repeated root reads.
- [x] Mirror shell output to a scrolling GOP framebuffer terminal. QEMU checks
  that a bottom-row newline moves earlier pixels up one glyph row.
- [x] Add a bounded shared key-event queue for non-serial devices, ANSI cursor
  controls, clear-screen support, and a visible framebuffer cursor.
- [x] Move line editing into a reusable line discipline: arrow-key movement,
  delete, bounded history, and clean redraw after asynchronous output. Keep
  the existing shell commands working on either console.
- **Exit check passed:** In QEMU, edit commands over serial and read a root file on
  both COM1 and the framebuffer without dropped characters, mixed output, or
  execution inside an IRQ. Keyboard input joins the same path in milestone 3.

### 2. Kernel services needed by live USB (complete)

- [x] Calibrate a monotonic timer and use deadline-based waits for controller
  commands, transfers, and key-repeat timing.
- [x] Add per-device IRQ registration and vector ownership, acknowledge device
  status in the handler, and queue completion work for normal kernel context.
  Reserve a vector distinct from storage vector `0x31` for xHCI.
- [x] Size PCI BARs, map their full MMIO ranges with the right cache attributes,
  and define DMA buffer ownership and synchronization. Reject unsupported IOMMU
  configurations explicitly until translation support exists.
- [x] Add a small event loop or scheduler so a blocked device operation does
  not stall serial input. Release command, transfer, and event allocations on
  both success and error paths.
- **Exit check passed:** Repeated IRQ registration, DMA allocation/release, MMIO
  map/unmap, and timeout cycles leave page counts stable. AHCI and NVMe QEMU
  runs retain COM1 input during intentionally delayed and failed requests while
  a complete xHCI BAR mapping remains owned for Stage 3.

### 3. Live xHCI and USB keyboard

- [x] Claim the PCI xHCI function, map its BAR, stop/reset it, and initialize
  DCBAA, scratchpads, command ring, event ring, and interrupter. Start with one
  controller and one device; report unsupported topology clearly.
- [x] Handle port changes, reset and enable a port, address a device, and make
  endpoint-zero control transfers. Read descriptors and select a configuration.
  Extend to interrupt endpoints, hotplug/unplug, and bounded controller reset
  and retry paths.
- [x] Connect the host-tested boot HID report parser to scheduled keyboard
  reports. Translate key down/up, modifiers, and repeat into the common input
  queue; make layout selection explicit (initially US).
- **Exit check passed:** QEMU `qemu-xhci` plus `usb-kbd` accepts shell input on the
  framebuffer while COM1 also works. Repeated plug/unplug and failed or delayed
  transfers recover without lost interrupts, leaked pages, or a stuck shell.
  The AHCI and NVMe matrix also queues USB input during a throttled root read,
  verifies deferred command execution, key repeat, framebuffer mirroring, three
  controller rebuilds, interrupt progress, and stable owned-page counts.

### 4. USB mass storage and mounted volumes

- [x] Implement live bulk endpoints and connect the existing MSC BOT protocol
  code to them. Discover capacity, read blocks through the common block-device
  interface, and handle SCSI sense, stalls, reset recovery, and removal.
- [x] Extend VFS with persistent file handles, mount identities, and streaming
  reads. Keep active reads safe when a USB device disappears. Add a read-only
  filesystem path for removable media; HyFS v1 has a flat directory, so nested
  paths require a filesystem extension or another filesystem driver.
- [x] Add shell commands for device listing, mounts, current directory, and
  incremental file display. Keep writes and safe eject as separate later work.
- **Exit check passed:** QEMU `usb-storage` mounts a second read-only volume and
  reads a 2 KiB file through MSC BOT on both AHCI and NVMe boots. Delayed reads
  retain queued COM1 input, and three attach/detach cycles fail atomically,
  rebuild the controller, reuse its DMA pages, and leave the boot root mounted.

### 5. User-facing terminal and programs (complete)

- [x] Finish nested path traversal, file descriptors, and consistent terminal
  read/write semantics. Add a basic command registry and useful inspection
  commands before introducing pipelines or background jobs.
- [x] Define the AUEX user program format, loader, syscall boundary, checked
  code/data address spaces, and bounded cooperative scheduler. Move command
  recognition into the user shell layer while the console supervisor retains
  device ownership and privileged services.
- **Exit check passed:** On AHCI and NVMe, an AUEX program reads edited terminal
  input and `/hello.txt`, exits cleanly, and returns every command allocation.
  A protected write faults without touching kernel memory. COM1 remains usable
  after that fault and after live USB removal.

Use [QEMU's USB device guide](https://www.qemu.org/docs/master/system/devices/usb.html)
for the emulated `qemu-xhci`, `usb-kbd`, and `usb-storage` integration matrix.
Keep host protocol tests for malformed descriptors, HID reports, BOT status,
timeouts, and transfer errors alongside the QEMU tests.

After these milestones, extend the same input path to a USB mouse and pointer
events, add hub and multi-device support to xHCI, then consider writable USB
media with flush and safe removal. Networking and a graphical window system
depend on the same scheduling, memory ownership, and device recovery work.

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
- [x] Add managed allocation ownership headers and explicit object, array,
  and string release, with page reuse and multi-page release stress checks.
- [x] Route AHCI MSI and NVMe MSI-X to storage vector `0x31`, acknowledge
  controller completions, and verify live QEMU read interrupt counters.
- [x] Track timeout, device error, reset, and retry exhaustion states; inject
  failed QEMU reads on both controllers and keep the serial shell responsive.
- [x] Stress repeated mapping, allocation/release, serial input, and root
  reads, including QEMU-throttled completion waits.
- [x] Add VFS file handles and namespace traversal, then test live I/O failure
  and removable-media invalidation paths. HyFS v1 remains a flat on-disk format.
- [ ] Establish keyboard and storage drivers.
- [x] Add host-tested Hylang USB protocol code for PCI xHCI discovery,
  controller stop/reset, descriptor selection, MSC BOT reads via a mock
  transport, and boot HID reports with a basic US keymap.
- [ ] Add driver-facing BAR sizing, dynamic MMIO mapping, IOMMU setup where
  present, timer calibration, and cache/DMA synchronization rules.
- [ ] Complete xHCI rings, port enumeration, control/bulk/interrupt transfers,
  then connect MSC and HID to the kernel's block and input queues.
- [x] Define the checked AUEX kernel/runtime boundary, loader, syscalls, and
  cooperative scheduler.
- [ ] Add native ring-3 processes, hardware privilege transitions, preemptive
  threads, and a native user-space runtime.

The running kernel is already independent of firmware boot services after the
handoff. These remaining stages turn its bootstrap into a fuller OS. Grow the
shared kernel services and their integration tests before adding more live
device drivers.

## Bootstrap note

Once a verified `hydrogen-stage1` binary exists, supported compiler and OS
builds do not require C++ or a host C compiler. A clean source-only compiler
checkout still needs a trusted Hydrogen seed or the initial SDK bootstrap route.
