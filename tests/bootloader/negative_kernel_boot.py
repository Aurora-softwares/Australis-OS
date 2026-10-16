#!/usr/bin/env python3
"""Reject missing or malformed AUKR kernels before the firmware handoff."""

from pathlib import Path
from tempfile import TemporaryDirectory
import shutil
import socket
import struct
import subprocess
import sys
import time


ERROR = b"[BOOT] Failed to start kernel."


def variant(kernel: bytes, name: str) -> bytes | None:
    if name == "missing":
        return None
    if name == "short":
        return kernel[:16]
    if name == "oversized":
        return kernel + bytes(1048577 - len(kernel))
    data = bytearray(kernel)
    if name == "bad-magic":
        data[0] ^= 1
    elif name == "bad-version":
        struct.pack_into("<I", data, 4, 2)
    elif name == "bad-length":
        struct.pack_into("<I", data, 8, len(data) - 15)
    elif name == "bad-entry":
        struct.pack_into("<I", data, 12, 17)
    else:
        raise ValueError(name)
    return bytes(data)


def check(qemu: str, firmware: str, base: Path, kernel: bytes,
          transport: str, name: str) -> None:
    with TemporaryDirectory(prefix=f"australis-boot-{transport}-{name}-") as directory:
        folder = Path(directory)
        image = folder / "boot.img"
        serial = folder / "serial.sock"
        shutil.copyfile(base, image)
        subprocess.run(["mdel", "-i", str(image),
                        "::EFI/AUSTRALIS/KERNEL.BIN"], check=True,
                       stdout=subprocess.DEVNULL)
        payload = variant(kernel, name)
        if payload is not None:
            source = folder / "kernel.bin"
            source.write_bytes(payload)
            subprocess.run(["mcopy", "-i", str(image), str(source),
                            "::EFI/AUSTRALIS/KERNEL.BIN"], check=True,
                           stdout=subprocess.DEVNULL)

        command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
                   f"if=pflash,format=raw,readonly=on,file={firmware}",
                   "-net", "none", "-display", "none", "-no-reboot",
                   "-monitor", "none", "-serial",
                   f"unix:{serial},server=on,wait=off"]
        if transport == "ahci":
            command += ["-device", "ich9-ahci,id=ahci0", "-drive",
                        f"if=none,id=sata0,format=raw,file={image}",
                        "-device", "ide-hd,drive=sata0,bus=ahci0.0"]
        else:
            command += ["-drive", f"if=none,id=nvme0,format=raw,file={image}",
                        "-device", "nvme,serial=australis,drive=nvme0"]
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 30
            while not serial.exists():
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open its serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(serial))
                received = bytearray()
                while ERROR not in received:
                    if process.poll() is not None:
                        raise RuntimeError(f"QEMU exited before boot rejection: {received[-500:]!r}")
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise TimeoutError(f"{transport} {name}: no rejection: {received[-500:]!r}")
                    connection.settimeout(min(remaining, 1))
                    try:
                        part = connection.recv(4096)
                    except socket.timeout:
                        continue
                    if not part:
                        raise RuntimeError(f"serial closed before rejection: {received[-500:]!r}")
                    received.extend(part)
                if b"[KERNEL]" in received or b"australis>" in received:
                    raise AssertionError(f"{transport} {name}: entered invalid kernel")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            process.stderr.close()


def main() -> None:
    qemu, firmware, base_image, kernel_path = sys.argv[1:5]
    kernel = Path(kernel_path).read_bytes()
    if kernel[:4] != b"AUKR" or len(kernel) <= 16 or len(kernel) >= 1048576:
        raise ValueError("the source kernel is not a valid AUKR test fixture")
    for transport in ("ahci", "nvme"):
        for name in ("missing", "short", "oversized", "bad-magic",
                     "bad-version", "bad-length", "bad-entry"):
            check(qemu, firmware, Path(base_image), kernel, transport, name)
            print(f"Australis {transport} {name} kernel rejected", flush=True)


if __name__ == "__main__":
    main()
