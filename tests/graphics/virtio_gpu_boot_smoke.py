#!/usr/bin/env python3
"""Exercise the modern VirtIO-GPU controlq and 2D resource path in QEMU."""

from pathlib import Path
from tempfile import TemporaryDirectory
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import read_until  # noqa: E402


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    iso = str(Path(iso).resolve())
    with TemporaryDirectory(prefix="australis-virtio-gpu-") as directory:
        serial = Path(directory) / "serial.sock"
        command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
                   f"if=pflash,format=raw,readonly=on,file={firmware}",
                   "-cdrom", iso, "-display", "none", "-net", "none",
                   "-no-reboot", "-vga", "std", "-device",
                   "virtio-gpu-pci,id=gpu0", "-serial",
                   f"unix:{serial},server=on,wait=off", "-monitor", "none"]
        if transport == "ahci":
            command += ["-device", "ich9-ahci,id=ahci0", "-drive",
                        f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
                        "-device", "ide-hd,drive=sata0,bus=ahci0.0"]
        else:
            command += ["-drive", f"if=none,id=nvme0,format=raw,readonly=on,file={iso}",
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
                opening = read_until(connection, b"australis> ", 90, process)
                if b"VirtIO-GPU 2D probe passed" not in opening:
                    raise AssertionError(f"native GPU probe failed: {opening[-3000:]!r}")
                connection.sendall(b"version\r")
                reply = read_until(connection, b"australis> ", 20, process)
                if b"Version: 0.0.1" not in reply:
                    raise AssertionError(f"shell failed after GPU probe: {reply[-2000:]!r}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} VirtIO-GPU 2D controlq passed")


if __name__ == "__main__":
    main()
