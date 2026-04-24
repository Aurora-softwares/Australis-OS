# Australis OS

Australis OS v0 is a tiny 64-bit x86 UEFI application written in C#.
It boots in a virtual machine, clears the screen, prints a fixed message,
and then stays on screen.

```text
Australis OS booted from C#
```

## Requirements

- `bflat` with UEFI support.
- `qemu-system-x86_64`.
- OVMF firmware at `/usr/share/OVMF/OVMF_CODE_4M.fd`.
- `mtools` commands: `mformat`, `mmd`, and `mcopy`.

If `bflat` is not on `PATH`, place it at `tools/bflat/bflat` or pass it
explicitly:

```bash
make build BFLAT=/path/to/bflat
```

On Linux, bflat also needs LLVM's C++ runtime library. If your system does
not already provide `libc++.so.1`, install the matching package, for example:

```bash
sudo apt install libc++1-18 libc++abi1-18 libunwind-18
```

## Build

```bash
make build
```

This compiles `src/boot/Program.cs` into:

```text
build/efi/EFI/BOOT/BOOTX64.EFI
```

The build uses:

```bash
bflat build --stdlib:zero --os:uefi --arch:x64 -o build/efi/EFI/BOOT/BOOTX64.EFI src/boot/Program.cs
```

## Image

```bash
make image
```

This creates a FAT UEFI image at:

```text
build/australis-uefi.img
```

## Run

```bash
make run
```

This launches QEMU with OVMF and boots the EFI application from
`build/efi/EFI/BOOT/BOOTX64.EFI`.

## Scope

This milestone is intentionally print-only. It does not include keyboard
input, a shell parser, filesystems, interrupts, Secure Boot, BIOS boot, or
Hydrogen integration yet.
