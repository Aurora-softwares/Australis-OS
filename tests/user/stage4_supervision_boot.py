#!/usr/bin/env python3
"""Boot a faulting shell and prove PID 1's restart bound and KMon fallback."""

from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from serial_boot_smoke import read_until  # noqa: E402
from system_image_recovery_smoke import boot_partition  # noqa: E402
from hyfs2 import Hyfs2Image  # noqa: E402


def main():
    qemu, firmware, source, fault_program, transport = sys.argv[1:6]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    with tempfile.TemporaryDirectory(prefix="australis-stage4-supervision-") as temp:
        directory = Path(temp)
        image = directory / "fault-shell.iso"
        volume = directory / "root.img"
        shutil.copyfile(source, image)
        first, last = boot_partition(image, volume)
        fs = Hyfs2Image.open(volume)
        fault = Path(fault_program).read_bytes()
        if not fault.startswith(b"AUEX"):
            raise AssertionError("fault fixture is not AUEX")
        fs.put("/System/Core/CommandShell.exec", fault)
        with image.open("r+b") as output:
            output.seek(first * 512)
            output.write(volume.read_bytes())
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
            command += ["-drive",
                        f"if=none,id=root0,format=raw,readonly=on,file={image}",
                        "-device", "nvme,serial=australis,drive=root0"]
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
                opening = read_until(connection, b"kmon> ", 90, process)
                if opening.count(b"System: service=CommandShell attempt=") != 3 or \
                        b"System: CommandShell restart limit reached" not in opening or \
                        b"australis> " in opening:
                    raise AssertionError(f"unbounded or failed shell recovery: {opening[-3000:]!r}")
                connection.sendall(b"help\r")
                response = read_until(connection, b"kmon> ", 20, process)
                if b"Commands: help" not in response:
                    raise AssertionError(f"KMon was unusable after shell faults: {response!r}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} bounded shell supervision passed")


if __name__ == "__main__":
    main()
