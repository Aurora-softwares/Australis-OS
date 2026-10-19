#!/usr/bin/env python3
"""A missing optional display service must leave the serial session usable."""

from pathlib import Path
from tempfile import TemporaryDirectory
import shutil
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "user"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from serial_boot_smoke import read_until  # noqa: E402
from system_image_recovery_smoke import boot_partition  # noqa: E402
from hyfs2 import Hyfs2Image  # noqa: E402


def main():
    qemu, firmware, source, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    with TemporaryDirectory(prefix="australis-display-fallback-") as directory:
        folder = Path(directory)
        image = folder / "missing-display.iso"
        volume = folder / "root.img"
        shutil.copyfile(source, image)
        first, last = boot_partition(image, volume)
        filesystem = Hyfs2Image.open(volume)
        filesystem.remove("/System/Core/Display.exec")
        contents = volume.read_bytes()
        if len(contents) != (last - first + 1) * 512:
            raise AssertionError("mutated boot partition changed size")
        with image.open("r+b") as output:
            output.seek(first * 512)
            output.write(contents)
        serial = folder / "serial.sock"
        command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
                   f"if=pflash,format=raw,readonly=on,file={firmware}",
                   "-cdrom", str(image), "-display", "none", "-net", "none",
                   "-no-reboot", "-serial",
                   f"unix:{serial},server=on,wait=off", "-monitor", "none"]
        if transport == "ahci":
            command += ["-device", "ich9-ahci,id=ahci0", "-drive",
                        f"if=none,id=sata0,format=raw,snapshot=on,file={image}",
                        "-device", "ide-hd,drive=sata0,bus=ahci0.0"]
        else:
            command += ["-drive", f"if=none,id=nvme0,format=raw,readonly=on,file={image}",
                        "-device", "nvme,serial=australis,drive=nvme0"]
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 30
            while not serial.exists():
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open the serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(serial))
                opening = read_until(connection, b"australis> ", 90, process)
                if b"System: display unavailable" not in opening:
                    raise AssertionError("missing display service blocked fallback")
                connection.sendall(b"version\r")
                reply = read_until(connection, b"australis> ", 20, process)
                if b"Version: 0.0.1" not in reply:
                    raise AssertionError("serial shell failed without display service")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} optional display fallback passed")


if __name__ == "__main__":
    main()
