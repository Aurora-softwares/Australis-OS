#!/usr/bin/env python3
"""Boot damaged HyFS 2 system images and verify independent KMon recovery."""

from pathlib import Path
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from serial_boot_smoke import read_until  # noqa: E402
from make_hyfs2_data_disk import BOOT_TYPE, SECTOR, read_gpt  # noqa: E402
from hyfs2 import Hyfs2Image  # noqa: E402

PROMPT = b"kmon> "
REQUIRED_DIRECTORIES = ("/System", "/System/Core", "/System/Config", "/System/Bin",
                        "/Applications", "/Users", "/Volumes", "/Temporary")
REQUIRED_FILES = ("/System/Core/System.exec", "/System/Core/CommandShell.exec",
                  "/System/Core/Device.exec", "/System/Core/Storage.exec",
                  "/System/Bin/cat.exec", "/System/Bin/ls.exec",
                  "/System/Bin/version.exec")


def boot_partition(image_path, volume_path):
    with image_path.open("rb") as image:
        _, entries = read_gpt(image)
        boot = [entries[i:i + 128] for i in range(0, len(entries), 128)
                if entries[i:i + 16] == BOOT_TYPE]
        if len(boot) != 1:
            raise AssertionError("expected exactly one HyFS boot partition")
        first, last = struct.unpack_from("<QQ", boot[0], 32)
        image.seek(first * SECTOR)
        volume_path.write_bytes(image.read((last - first + 1) * SECTOR))
    return first, last


def prepare(source, destination, volume_path, damage):
    shutil.copyfile(source, destination)
    first, last = boot_partition(destination, volume_path)
    filesystem = Hyfs2Image.open(volume_path)
    for directory in REQUIRED_DIRECTORIES:
        if filesystem.stat(directory).kind != 2:
            raise AssertionError(f"missing packaged directory {directory}")
    for path in REQUIRED_FILES:
        if not filesystem.read_file(path).startswith(b"AUEX"):
            raise AssertionError(f"missing source-built executable {path}")
    if not filesystem.read_file("/System/Config/startup.manifest").startswith(b"AUSM1\n"):
        raise AssertionError("missing versioned startup manifest")
    if damage == "missing":
        filesystem.remove("/System/Core/System.exec")
    elif damage == "malformed":
        filesystem.put("/System/Core/System.exec", b"invalid AUEX payload")
    elif damage == "manifest":
        filesystem.put("/System/Config/startup.manifest", b"AUSM9\n")
    elif damage == "manifest-late":
        filesystem.put("/System/Config/startup.manifest",
                       b"AUSM1\nDevice|/System/Core/Device.exec|2|5000|O\n"
                       b"Storage|relative.exec|2|5000|O\n")
    elif damage == "metadata":
        with volume_path.open("r+b") as volume:
            volume.write(bytes(2 * SECTOR))
    else:
        raise ValueError(damage)
    data = volume_path.read_bytes()
    if len(data) != (last - first + 1) * SECTOR:
        raise AssertionError("mutated boot partition changed size")
    with destination.open("r+b") as image:
        image.seek(first * SECTOR)
        image.write(data)


def boot(qemu, firmware, image, transport, directory, damage):
    serial = directory / "serial.sock"
    command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
               f"if=pflash,format=raw,readonly=on,file={firmware}",
               "-cdrom", str(image), "-display", "none", "-net", "none",
               "-no-reboot", "-serial", f"unix:{serial},server=on,wait=off",
               "-monitor", "none"]
    if transport == "ahci":
        command += ["-device", "ich9-ahci,id=ahci0", "-drive",
                    f"if=none,id=root0,format=raw,snapshot=on,file={image}",
                    "-device", "ide-hd,drive=root0,bus=ahci0.0"]
    else:
        command += ["-drive", f"if=none,id=root0,format=raw,readonly=on,file={image}",
                    "-device", "nvme,serial=australis,drive=root0"]
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL,
                               stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 45
        while not serial.exists():
            if process.poll() is not None:
                raise RuntimeError(process.stderr.read().decode(errors="replace"))
            if time.monotonic() >= deadline:
                raise TimeoutError(f"QEMU did not open serial socket for {damage}")
            time.sleep(0.05)
        with socket.socket(socket.AF_UNIX) as connection:
            connection.connect(str(serial))
            opening = read_until(connection, PROMPT, 90, process)
            if b"australis> " in opening:
                raise AssertionError(f"{damage} entered userland: {opening[-1500:]!r}")
            if damage in ("manifest", "manifest-late"):
                if (b"System: invalid startup manifest" not in opening or
                        b"System failed; entering KMon." not in opening):
                    raise AssertionError(f"{damage} missed PID 1 fallback: {opening[-1500:]!r}")
                if damage == "manifest-late" and b"service=Device" in opening:
                    raise AssertionError("PID 1 started a service before validating all records")
            elif damage != "metadata" and b"System executable unavailable" not in opening:
                raise AssertionError(f"{damage} missed PID 1 fallback: {opening[-1500:]!r}")
            connection.sendall(b"help\r")
            help_output = read_until(connection, PROMPT, 20, process)
            if b"Commands: help" not in help_output:
                raise AssertionError(f"KMon failed after {damage}: {help_output!r}")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def main():
    qemu, firmware, source, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    with tempfile.TemporaryDirectory(prefix="australis-system-recovery-") as temporary:
        directory = Path(temporary)
        for damage in ("missing", "malformed", "manifest", "manifest-late", "metadata"):
            case = directory / damage
            case.mkdir()
            image = case / "damaged.iso"
            prepare(Path(source), image, case / "volume.img", damage)
            boot(qemu, firmware, image, transport, case, damage)
    print(f"Australis {transport.upper()} system-image recovery passed")


if __name__ == "__main__":
    main()
