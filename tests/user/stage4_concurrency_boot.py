#!/usr/bin/env python3
"""Boot two independent AUEX children through the userland shell."""

from pathlib import Path
from tempfile import TemporaryDirectory
import re
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import read_until  # noqa: E402


def main() -> None:
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    iso = str(Path(iso).resolve())
    with TemporaryDirectory(prefix="australis-concurrency-") as directory:
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
            command += ["-drive", f"if=none,id=nvme0,format=raw,readonly=on,file={iso}",
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
                opening = read_until(connection, b"australis> ", 90, process)
                connection.sendall(b"run /System/Bin/concurrent-probe.exec\r")
                response = read_until(connection, b"australis> ", 90, process)
                if b"System: service=CommandShell ready pid=" not in opening + response:
                    raise AssertionError(f"shell did not report readiness: {(opening + response)[-2000:]!r}")
                order = re.findall(rb"concurrent-([ab])\r\n", response)
                if (order.count(b"a") != 12 or order.count(b"b") != 12 or
                        b"concurrent-probe: passed" not in response or
                        len([i for i in range(1, len(order)) if order[i] != order[i - 1]]) < 2):
                    raise AssertionError(f"children did not overlap cleanly: {response[-3500:]!r}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} concurrent AUEX children passed")


if __name__ == "__main__":
    main()
