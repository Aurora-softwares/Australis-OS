#!/usr/bin/env python3
"""Boot the EFI-only image into kernel rescue without a HyFS partition."""

from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from serial_boot_smoke import monitor_command, read_until  # noqa: E402


def main():
    qemu, firmware, image = sys.argv[1:4]
    with tempfile.TemporaryDirectory(prefix="australis-rescue-") as temporary:
        serial_path = str(Path(temporary) / "serial.sock")
        monitor_path = str(Path(temporary) / "monitor.sock")
        command = [
            qemu, "-machine", "q35", "-m", "256M",
            "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
            "-device", "ich9-ahci,id=ahci0",
            "-drive", f"if=none,id=sata0,format=raw,snapshot=on,file={image}",
            "-device", "ide-hd,drive=sata0,bus=ahci0.0",
            "-device", "qemu-xhci,id=xhci0", "-device", "usb-kbd,bus=xhci0.0",
            "-display", "none", "-net", "none", "-no-reboot",
            "-serial", f"unix:{serial_path},server=on,wait=off",
            "-monitor", f"unix:{monitor_path},server=on,wait=off",
        ]
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 15
            while not Path(serial_path).exists() or not Path(monitor_path).exists():
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open its sockets")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as serial:
                serial.connect(serial_path)
                serial.settimeout(0.2)
                opening = bytearray()
                deadline = time.monotonic() + 30
                while b"rescue> " not in opening:
                    if process.poll() is not None:
                        raise RuntimeError(process.stderr.read().decode(errors="replace"))
                    if time.monotonic() >= deadline:
                        raise AssertionError(f"rescue prompt missing: {opening[-500:]!r}")
                    monitor_command(monitor_path, "sendkey r 70")
                    try:
                        opening.extend(serial.recv(4096))
                    except socket.timeout:
                        pass
                    if b"kmon> " in opening:
                        raise AssertionError("boot reached normal KMon instead of Rescue")
                serial.sendall(b"help\r")
                response = read_until(serial, b"\nrescue> ", 15, process)
                if b"Commands: help" not in response:
                    raise AssertionError(f"rescue help failed: {response!r}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print("Australis EFI-only rescue boot passed")


if __name__ == "__main__":
    main()
