# Australis OS

Australis OS is a minimal x86_64 UEFI proof of concept authored in Hylang. It
boots directly from a UEFI ISO, writes a message to the firmware console, and
then remains on screen:

```text
Hello world from Hylang!
```

This is deliberately a small compiler-target proof, not a kernel or general
UEFI runtime. The initial `uefi-x64` Hylang target accepts a `Main` method with
one `System.Console.WriteLine` ASCII string literal and emits the PE32+ EFI
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

This compiles [`src/boot/Program.hy`](src/boot/Program.hy) into a native UEFI
application and produces:

```text
build/efi/EFI/BOOT/BOOTX64.EFI
build/australis-hylang-hello.iso
```

The ISO contains a FAT EFI boot image at its El Torito UEFI boot entry. A raw
FAT UEFI disk image is also available through:

```bash
make image
```

at `build/australis-hylang-uefi.img`.

## Run

```bash
make run
```

This boots `build/australis-hylang-hello.iso` in QEMU with OVMF. Override the
default locations when needed:

```bash
make run HYDROGEN=/path/to/hydrogen-stage1 OVMF_CODE=/path/to/OVMF_CODE.fd
```

## Scope

The UEFI target is intentionally limited to the one-line hello-world proof.
It has no keyboard support, shell, filesystem, allocator, drivers, general
method compilation, or post-boot-services kernel handoff yet. Those need a
defined firmware ABI, memory model, and freestanding runtime before they can
be added safely.
