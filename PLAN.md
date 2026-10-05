# Australis OS Active Plan

This plan records the current, Hydrogen-first path. It is a companion to the
Australis documentation and the Hylang compiler's OS roadmap.

## Current capability: v0 proof of concept

Australis currently proves one narrow but important path end to end:

- `src/boot/Program.hy` is compiled by the retained self-hosted
  `hydrogen-stage1` compiler.
- `--target uefi-x64` emits a PE32+ x86-64 EFI application with an EFI entry
  point, UTF-16 output, and a direct UEFI text-console call.
- `mtools` and `xorriso` package that application into either a FAT disk image
  or an El Torito UEFI ISO. They do not compile Hydrogen.
- QEMU with OVMF boots the ISO and displays `Hello world from Hylang!`.

The current EFI target is intentionally restricted. It supports the static
entry-point console demonstration—ASCII literals passed to
`System.Console.WriteLine`—and is not yet a general UEFI runtime, standard
library, command shell, or independent kernel.

## Completed

- [x] Self-hosted compiler emits a PE32+ x86-64 UEFI image.
- [x] UEFI entry-point ABI and firmware console function-pointer call.
- [x] UTF-16 encoding for the firmware console string.
- [x] `src/boot/Program.hy` is the sole current boot source; the old C# source
  was removed.
- [x] `make build`, `make image`, `make iso`, and `make run` use the
  self-hosted compiler plus packaging tools.
- [x] Boot the generated ISO in QEMU/OVMF and verify the text output.

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

- [ ] Obtain and preserve the UEFI memory map.
- [ ] Call `ExitBootServices` successfully and continue execution.
- [ ] Implement allocation and framebuffer output without firmware services.
- [ ] Establish interrupt, keyboard, and storage drivers.
- [ ] Define a kernel/runtime boundary, then introduce userland and syscalls as
  the system matures.

At that point Australis becomes independent of the firmware runtime rather than
an EFI application that uses it. The sequence matters: build and test the
compiler/library contracts first, then depend on them for the shell and kernel.

## Bootstrap note

Once a verified `hydrogen-stage1` binary exists, supported compiler and OS
builds do not require C++ or a host C compiler. A clean source-only compiler
checkout still needs a trusted Hydrogen seed or the initial SDK bootstrap route.
