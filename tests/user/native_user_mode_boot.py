#!/usr/bin/env python3
"""Prove ring-3 launch, syscall return, and contained user faults."""

from pathlib import Path
from tempfile import TemporaryDirectory
import re
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import read_until  # noqa: E402


def read_opening(connection, process):
    deadline = time.monotonic() + 90
    received = bytearray()
    while b"australis> " not in received and b"kmon> " not in received:
        if process.poll() is not None:
            raise RuntimeError(f"QEMU exited with status {process.returncode}")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"serial output timed out: {bytes(received[-500:])!r}")
        connection.settimeout(min(remaining, 1))
        try:
            part = connection.recv(4096)
        except socket.timeout:
            continue
        if not part:
            raise RuntimeError(f"serial connection closed: {bytes(received[-500:])!r}")
        received.extend(part)
    return bytes(received)


def main() -> None:
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    iso = str(Path(iso).resolve())
    with TemporaryDirectory(prefix="australis-native-user-") as directory:
        serial = Path(directory) / "serial.sock"
        command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
                   f"if=pflash,format=raw,readonly=on,file={firmware}",
                   "-cdrom", iso, "-net", "none", "-display", "none",
                   "-no-reboot", "-serial",
                   f"unix:{serial},server=on,wait=off", "-monitor", "none"]
        if transport == "ahci":
            command += ["-device", "ich9-ahci,id=ahci0", "-drive",
                        f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
                        "-device", "ide-hd,drive=sata0,bus=ahci0.0"]
        else:
            command += ["-drive",
                        f"if=none,id=nvme0,format=raw,readonly=on,file={iso}",
                        "-device", "nvme,serial=australis,drive=nvme0"]
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 45
            while not serial.exists():
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open the serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(serial))
                opening = read_opening(connection, process)
                if b"native-user: isolation passed" not in opening:
                    raise AssertionError(
                        f"native fault containment failed: {opening[-3500:]!r}")
                for image, expected in (
                    ("native-pid", b"shell: exit status "),
                    ("native-hydrogen", b"hydrogen-aun1-ok"),
                    ("native-write-invalid", b"native-invalid-pointers-ok"),
                    ("native-fault", b"shell: program fault: -103"),
                    ("native-privilege", b"shell: program fault: -102"),
                ):
                    connection.sendall(
                        f"run /System/Bin/{image}.exec\r".encode("ascii"))
                    response = read_until(connection, b"australis> ", 30, process)
                    if expected not in response:
                        raise AssertionError(
                            f"{image} failed: {response[-3500:]!r}")
                    if image == "native-pid":
                        status = re.search(rb"shell: exit status (\d+)", response)
                        if status is None or int(status.group(1)) in (0, 99):
                            raise AssertionError(f"invalid native PID: {response!r}")
                    if image == "native-hydrogen" and b"shell: exit status 7" not in response:
                        raise AssertionError(f"wrong Hydrogen exit status: {response!r}")
                connection.sendall(b"help\r")
                help_text = read_until(connection, b"australis> ", 30, process)
                if b"Built-ins: help" not in help_text:
                    raise AssertionError(f"PID 1 shell failed after fault: {help_text!r}")
                connection.sendall(b"exit\r")
                recovery = read_until(connection, b"kmon> ", 30, process)
                if b"System session ended; entering KMon." not in recovery:
                    raise AssertionError(f"KMon recovery failed: {recovery!r}")
                connection.sendall(b"help\r")
                response = read_until(connection, b"kmon> ", 30, process)
                if b"Commands: help" not in response:
                    raise AssertionError(f"KMon unusable after native fault: {response!r}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} native user fault containment passed")


if __name__ == "__main__":
    main()
