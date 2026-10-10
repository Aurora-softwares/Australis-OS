# Bootloader completion criteria

This checklist was audited against `program.hy`, the self-hosted UEFI image
emitter, the documented `KernelBootInfo` ABI, and the AHCI/NVMe QEMU boot
tests.

Status key: `[x]` implemented and exercised, `[~]` partially complete, and
`[ ]` not implemented.

## Stage 1 - Minimum Viable Bootloader

| Done | Requirement | Evidence |
| --- | --- | --- |
| [x] | UEFI support | `BOOTX64.EFI` boots under x86-64 OVMF from optical and disk images. |
| [x] | Kernel discovery | Opens `\EFI\AUSTRALIS\KERNEL.BIN` through the boot volume's Simple File System protocol. |
| [x] | Kernel loading | Reads the complete image into `EfiLoaderCode` memory and rejects short reads. |
| [x] | Memory allocation | Allocates the image, a 64 KiB kernel stack, boot information, page tables, heap pages, and reserved DMA pages. |
| [x] | Kernel entry point | Validates the AUKR v1 header, exact code length, and entry offset `16`. |
| [x] | Boot information | Passes the versioned `KernelBootInfo` pointer to `KernelMain.Run` in `RDI`. |
| [x] | UEFI handover | Captures the final map and retries `ExitBootServices` with a fresh map key when required. |
| [x] | Execution transfer | Switches to the dedicated stack and calls the position-independent raw kernel entry. |
| [x] | Error handling | Firmware load, allocation, file, image-validation, memory-map, and GOP failures reach visible error paths. |
| [x] | Debug output | Emits the `[BOOT]` loading and handoff milestones before leaving firmware services. |

**Stage 1 result: complete.** The complete handoff reaches the interactive
kernel on both AHCI and NVMe QEMU configurations.

## Stage 2 - Feature Complete Bootloader

| Done | Requirement | Current evidence or remaining work | Priority |
| --- | --- | --- | --- |
| [x] | UEFI boot | Emits a PE32+ EFI application with the Microsoft x64 UEFI entry ABI. | Essential |
| [x] | Kernel loading | Validates AUKR magic, version, size, code length, and entry offset before handoff. | Essential |
| [x] | Memory map | Preserves map address, byte length, descriptor size, and descriptor version. | Essential |
| [x] | Memory allocation | Uses firmware loader allocations before handoff, then only conventional-memory descriptors afterwards. | Essential |
| [x] | Video initialization | Captures GOP geometry and pixel format before handoff and renders directly afterwards. | Essential |
| [x] | Boot information | Uses the `AUBI` record at ABI version 7 with a documented field layout. | Essential |
| [ ] | ACPI discovery | Pass the ACPI RSDP location when available. | Recommended |
| [ ] | Kernel parameters | Support configurable kernel arguments. | Recommended |
| [ ] | Boot configuration | Read boot settings from a configuration file. | Recommended |
| [~] | Debug mode | Boot milestones are always enabled; there is no selectable detailed-debug mode. | Essential |
| [ ] | Silent mode | Boot without unnecessary output. | Essential |
| [x] | Error handling | Missing/open/read failures and malformed or unsupported AUKR images stop on the firmware error path. Negative-path QEMU automation is still required. | Essential |
| [x] | UEFI exit | Retries final map capture and exits with the current map key. | Essential |
| [x] | Kernel handover | The documented contract passes `KernelBootInfo` in `RDI` on a dedicated stack. | Essential |
| [~] | Boot device support | Hybrid ISO and disk boot paths pass under OVMF with AHCI and NVMe; physical USB and internal-drive firmware coverage remains. | Essential |
| [ ] | Multiple architectures | Support ARM64 or additional architectures. | Future |
| [ ] | Secure Boot | Support signed bootloader binaries and a trusted boot chain. | Future |
| [ ] | Recovery support | Provide recovery or alternative boot options. | Optional |

**Stage 2 result: in progress.** The core handoff features are implemented.
Configurable logging, silent boot, physical-media validation, and the listed
recommended and future capabilities remain open.

## Stage 3 - Production Ready

Before considering the bootloader finished for a stable Australis release:

- [~] Reliable booting on QEMU and multiple physical UEFI systems. AHCI and
  NVMe QEMU coverage passes; physical systems remain untested.
- [ ] Consistent behaviour across physical cold boots and restarts.
- [x] Validation of kernel size, AUKR header, version, code length, exact read,
  and entry offset.
- [~] Clean handling of allocation failures and unavailable hardware features.
  Error paths exist, but failure injection is incomplete.
- [x] No dependency on UEFI boot services after the handover.
- [x] Versioned compatibility through AUKR v1 and `KernelBootInfo` ABI v7.
- [~] Automated tests for loading and handover. Positive AHCI/NVMe paths pass;
  missing and corrupted kernel images are not yet injected in QEMU.
- [ ] No known critical boot or memory corruption bugs across the supported
  physical hardware matrix.

**Stage 3 result: not complete.** The next bootloader-specific work is negative
image and handoff testing, ACPI discovery, boot configuration and modes, and
validation on physical UEFI machines.

## Completion definition

The bootloader is complete for a stable Australis release when it can reliably
discover, validate, load, and execute an Australis kernel on supported hardware,
provide all required boot information, handle failures gracefully, and leave
the firmware environment cleanly.
