#!/usr/bin/env python3
"""Check paced GOP submissions and live latency after a mouse workload."""

from pathlib import Path
from tempfile import TemporaryDirectory
import re
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import monitor_command, read_until  # noqa: E402


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    iso = str(Path(iso).resolve())
    with TemporaryDirectory(prefix="australis-frame-pacing-") as directory:
        serial = Path(directory) / "serial.sock"
        monitor = Path(directory) / "monitor.sock"
        command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
                   f"if=pflash,format=raw,readonly=on,file={firmware}",
                   "-cdrom", iso, "-display", "none", "-net", "none",
                   "-no-reboot", "-device", "qemu-xhci,id=xhci0",
                   "-device", "usb-kbd,bus=xhci0.0", "-device",
                   "usb-mouse,bus=xhci0.0", "-serial",
                   f"unix:{serial},server=on,wait=off", "-monitor",
                   f"unix:{monitor},server=on,wait=off"]
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
            while not serial.exists() or not monitor.exists():
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open its sockets")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(serial))
                opening = read_until(connection, b"australis> ", 90, process)
                if b"System: display ready" not in opening:
                    raise AssertionError(f"display unavailable: {opening[-2000:]!r}")
                for index in range(16):
                    delta = 20 if index % 2 == 0 else -20
                    monitor_command(str(monitor), f"mouse_move {delta} 0")
                    time.sleep(0.09)
                report = read_until(connection, b"Display: paced frames=", 30,
                                    process)
                tail = report[report.rfind(b"Display: paced frames="):]
                if b"\n" not in tail:
                    report += read_until(connection, b"\n", 10, process)
                match = re.search(
                    rb"Display: paced frames=(\d+) last_us=(\d+) "
                    rb"max_us=(\d+) waits=(\d+)", report)
                if not match:
                    raise AssertionError(f"missing pacing metrics: {report[-2000:]!r}")
                frames, last_us, max_us, waits = map(int, match.groups())
                if frames < 2 or last_us <= 0 or max_us < last_us or (
                    max_us > 10_000_000 or waits < 1
                ):
                    raise AssertionError(
                        f"bad live pacing: frames={frames}, last={last_us}, "
                        f"max={max_us}, waits={waits}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} GOP frame pacing passed: "
          f"frames={frames}, last_us={last_us}, max_us={max_us}, "
          f"waits={waits}")


if __name__ == "__main__":
    main()
