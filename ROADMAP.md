# Australis OS roadmap

This file tracks **OS development milestones**, not component ABI versions or
published releases. The detailed implementation plan is in [PLAN.md](PLAN.md);
subsystem completion criteria are in the
[bootloader](src/bootloader/README.md) and [kernel](src/kernel/README.md) notes.

## Current position

**Recommended development version: `0.0.7`.** The working tree has a booting
Hylang kernel, read-only HyFS, a terminal shell, USB input and storage, and
checked AUEX programs with a cooperative scheduler. The next milestone is
native user mode. This assessment describes source capability; it is not a
claim that `0.0.7` has been tagged or released.

Version metadata needs alignment when this milestone is adopted: the shell,
kernel project, and bootloader project still report `0.0.1`, while the top-level
OS project declares `0.1.0`. Neither currently identifies the development
milestone accurately. AUKR, AUEX, HyFS, and boot-information ABI versions are
separate format versions and should not be changed to match the OS version.

## Milestones

The completed rows describe the **minimum working scope** reached in the
current development tree. They do not imply that each subsystem is feature
complete or validated on physical hardware.

| Version | Status | Bootloader | Kernel and system exit criterion |
| --- | --- | --- | --- |
| `0.0.1` | Implemented | Load and enter a separate kernel image. | Boot and print through the kernel console. |
| `0.0.2` | Implemented | Pass versioned boot information. | Initialise essential CPU state and capture exceptions. |
| `0.0.3` | Implemented | Hand over the final memory map and leave boot services. | Allocate physical pages, manage virtual mappings, and run on a kernel stack. |
| `0.0.4` | Implemented | Report boot progress and handoff errors. | Provide a heap, calibrated timer, interrupts, and an interactive serial terminal. |
| `0.0.5` | Implemented | Validate the kernel image before entry. | Read AHCI/NVMe block devices, discover GPT partitions, and expose a VFS. |
| `0.0.6` | Implemented | Boot the storage-backed kernel under QEMU/OVMF. | Mount read-only HyFS, read files, and accept USB keyboard input and USB storage through xHCI. |
| `0.0.7` | Current development milestone | Maintain the existing handoff. | Run an initial shell and checked AUEX programs with file descriptors, terminal calls, bounded cooperative scheduling, and fault cleanup. |
| `0.0.8` | Next | Keep the handoff compatible with native processes. | Execute native programs in ring 3 with hardware-enforced address spaces, a native system-call entry, and context switching. |
| `0.0.9` | Planned | Add selectable debug/silent modes and boot configuration. | Add writable HyFS operations, flush/recovery semantics, and a usable persistent shell environment. |
| `0.1.0` | Planned stable baseline | Pass negative-path boot tests and supported physical UEFI boot checks. | Pass the release test matrix and provide a stable foundational kernel and basic usable environment. |

## Outstanding work before `0.1.0`

- **Processes and isolation:** AUEX currently runs in a checked interpreter.
  Native ring-3 execution, hardware privilege separation, native system calls,
  context switching, and preemptive threads remain open.
- **Writable storage:** HyFS and removable USB volumes are read-only. On-disk
  directories, write and flush support, recovery, and safe removal remain open.
- **Boot experience:** Boot progress output is always enabled. Selectable
  debug/silent modes, configuration, ACPI discovery, and negative-path QEMU
  coverage remain open.
- **Device breadth and release validation:** xHCI supports one root device at a
  time. Hubs, multiple simultaneous devices, broader hardware coverage, and
  physical-machine validation remain open.

For the current integration checks, see `make test-stage3`, `make test-stage4`,
and `make test-stage5` in the [Makefile](Makefile). A stable release also needs
the completion gates documented in the bootloader and kernel notes above.
