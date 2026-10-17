#!/usr/bin/env python3
"""Check normal, explicit silent, and default silent boot selections."""

from pathlib import Path
from tempfile import TemporaryDirectory
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import monitor_command, read_until  # noqa: E402


def boot(qemu: str, firmware: str, iso: str, key: str | None,
         expected_mode: int) -> None:
    with TemporaryDirectory(prefix="australis-boot-mode-") as directory:
        serial = Path(directory) / "serial.sock"
        monitor = Path(directory) / "monitor.sock"
        command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
                   f"if=pflash,format=raw,readonly=on,file={firmware}",
                   "-cdrom", iso, "-net", "none", "-display", "none",
                   "-no-reboot", "-serial",
                   f"unix:{serial},server=on,wait=off", "-monitor",
                   f"unix:{monitor},server=on,wait=off", "-device",
                   "ich9-ahci,id=ahci0", "-drive",
                   f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
                   "-device", "ide-hd,drive=sata0,bus=ahci0.0"]
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 75
            while not serial.exists() or not monitor.exists():
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open its sockets")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(serial))
                output = bytearray()
                last_key = 0.0
                while b"australis> " not in output:
                    if process.poll() is not None:
                        raise RuntimeError(f"QEMU exited during boot: {output[-500:]!r}")
                    if time.monotonic() >= deadline:
                        raise TimeoutError(f"no system shell: {output[-500:]!r}")
                    if key is not None and time.monotonic() - last_key >= 0.5:
                        monitor_command(str(monitor), f"sendkey {key} 70")
                        last_key = time.monotonic()
                    connection.settimeout(0.2)
                    try:
                        output.extend(connection.recv(4096))
                    except socket.timeout:
                        pass
                connection.sendall(b"\x15exit\r")  # clear queued boot keys
                recovery = read_until(connection, b"kmon> ", 25, process)
                if b"System session ended; entering KMon." not in recovery:
                    raise AssertionError(f"KMon missing after shell exit: {recovery[-500:]!r}")
                connection.sendall(b"trace\r")
                trace = read_until(connection, b"kmon> ", 15, process)
                expected = f"boot mode: {expected_mode}".encode()
                if expected not in trace:
                    raise AssertionError(f"{key or 'default'} expected {expected!r}: {trace[-900:]!r}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            process.stderr.close()


def main() -> None:
    qemu, firmware, iso = sys.argv[1:4]
    for key, mode in ((None, 2), ("s", 2), ("n", 0)):
        boot(qemu, firmware, iso, key, mode)
        print(f"Australis {key or 'default'} boot mode passed", flush=True)


if __name__ == "__main__":
    main()
