#!/usr/bin/env python3
"""Exercise AUN1 VFS handles on writable AHCI and NVMe data volumes."""

from pathlib import Path
from tempfile import TemporaryDirectory
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from hyfs2 import Hyfs2Image, scan_image  # noqa: E402
from make_hyfs2_data_disk import create  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import read_until  # noqa: E402
from native_user_mode_boot import read_opening  # noqa: E402


def run(qemu, firmware, iso, disk, transport, temporary):
    serial = temporary / "serial.sock"
    command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
               f"if=pflash,format=raw,readonly=on,file={firmware}",
               "-cdrom", str(iso), "-net", "none", "-display", "none",
               "-no-reboot", "-serial", f"unix:{serial},server=on,wait=off",
               "-monitor", "none", "-drive",
               f"if=none,id=data0,format=raw,file={disk}"]
    if transport == "ahci":
        command += ["-device", "ich9-ahci,id=ahci0", "-device",
                    "ide-hd,drive=data0,bus=ahci0.0"]
    else:
        command += ["-device", "nvme,serial=australis-data,drive=data0"]
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
                raise AssertionError(f"native boot failed: {opening[-1000:]!r}")
            # More runs than the 16 native file-table slots reveal leaked
            # per-process descriptors or tables after exit.
            for _ in range(18):
                connection.sendall(b"run /System/Bin/native-files.exec\r")
                response = read_until(connection, b"australis> ", 40, process)
                if (b"native-files: passed" not in response or
                        b"shell: exit status 37" not in response):
                    raise AssertionError(f"native file probe failed: {response[-3500:]!r}")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def check_disk(disk, first, blocks, temporary):
    partition = temporary / "data.hyfs2"
    with disk.open("rb") as source, partition.open("wb") as target:
        source.seek(first * 512)
        remaining = blocks * 512
        while remaining:
            chunk = source.read(min(remaining, 1024 * 1024))
            if not chunk:
                raise AssertionError("short data partition")
            target.write(chunk)
            remaining -= len(chunk)
    list(scan_image(partition))
    image = Hyfs2Image.open(partition)
    if image.read_file("/native-file-check") != b"ABC":
        raise AssertionError("native file contents did not survive shutdown")


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    iso = Path(iso).resolve()
    with TemporaryDirectory(prefix="australis-native-files-") as directory:
        temporary = Path(directory)
        disk = temporary / "data.img"
        first, blocks = create(iso, disk)
        for boot in range(2):
            session = temporary / f"boot-{boot}"
            session.mkdir()
            run(qemu, firmware, iso, disk, transport, session)
            check_disk(disk, first, blocks, temporary)
    print(f"Australis {transport.upper()} native file handles passed")


if __name__ == "__main__":
    main()
