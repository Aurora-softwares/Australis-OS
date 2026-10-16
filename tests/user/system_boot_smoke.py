#!/usr/bin/env python3
"""Check the normal boot handoff from PID 1 to the userland shell."""

from pathlib import Path
from tempfile import TemporaryDirectory
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import PROMPT, read_until  # noqa: E402


def main() -> None:
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    iso = str(Path(iso).resolve())
    with TemporaryDirectory(prefix="australis-system-boot-") as directory:
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
            deadline = time.monotonic() + 15
            while not serial.exists():
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open the serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(serial))
                opening = read_until(connection, b"australis> ", 90, process)
                if (b"Australis command shell" not in opening or
                        PROMPT in opening):
                    raise AssertionError(f"normal boot missed PID 1 shell: {opening!r}")
                connection.sendall(b"help\r")
                help_text = read_until(connection, b"australis> ", 30, process)
                if b"Built-ins: help cd pwd path set export unset history exit" not in help_text:
                    raise AssertionError(f"shell help failed: {help_text!r}")
                connection.sendall(b"exit\r")
                fallback = read_until(connection, PROMPT, 30, process)
                if b"System session ended; entering KMon." not in fallback:
                    raise AssertionError(f"ended session missed KMon: {fallback!r}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} PID 1 shell boot passed")


if __name__ == "__main__":
    main()
