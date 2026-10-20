#!/usr/bin/env python3
"""Keep the native cursor responsive without leaking managed kernel pages."""

from pathlib import Path
from tempfile import TemporaryDirectory
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import capture_record, monitor_command, read_until  # noqa: E402


def main():
    qemu, firmware, iso = sys.argv[1:4]
    iso = str(Path(iso).resolve())
    with TemporaryDirectory(prefix="australis-cursor-stress-") as directory:
        directory = Path(directory)
        serial = directory / "serial.sock"
        monitor = directory / "monitor.sock"
        command = [
            qemu, "-machine", "q35", "-m", "256M", "-drive",
            f"if=pflash,format=raw,readonly=on,file={firmware}",
            "-cdrom", iso, "-display", "none", "-net", "none", "-no-reboot",
            "-vga", "none", "-device", "virtio-vga,id=gpu0",
            "-device", "qemu-xhci,id=xhci0", "-device", "usb-kbd,bus=xhci0.0",
            "-device", "usb-mouse,bus=xhci0.0", "-serial",
            f"unix:{serial},server=on,wait=off", "-monitor",
            f"unix:{monitor},server=on,wait=off", "-device", "ich9-ahci,id=ahci0",
            "-drive", f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
            "-device", "ide-hd,drive=sata0,bus=ahci0.0",
        ]
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
                if b"VirtIO-GPU scanout cursor active" not in opening:
                    raise AssertionError("native cursor was not activated")
                time.sleep(4)
                before = capture_record(str(monitor), directory / "before.bin")
                time.sleep(3)
                idle = capture_record(str(monitor), directory / "idle.bin")
                for index in range(300):
                    delta = 4 if index % 2 == 0 else -4
                    monitor_command(str(monitor), f"mouse_move {delta} 0")
                    time.sleep(0.01)
                time.sleep(2)
                moved = capture_record(str(monitor), directory / "moved.bin")
                connection.sendall(b"version\r")
                response = read_until(connection, b"australis> ", 30, process)
                idle_growth = idle["allocator_next"] - before["allocator_next"]
                mouse_growth = moved["allocator_next"] - idle["allocator_next"]
                reports = moved["xhci_reports"] - idle["xhci_reports"]
                if (b"Version: 0.0.1" not in response or reports < 100 or
                        idle_growth < 0 or idle_growth > 262144 or
                        mouse_growth < 0 or mouse_growth > 262144 or
                        moved["memory_error"] != 0 or moved["panic_vector"] != 0):
                    raise AssertionError(
                        f"cursor stress failed: reports={reports}, "
                        f"idle_growth={idle_growth}, mouse_growth={mouse_growth}, "
                        f"memory_error={moved['memory_error']}, "
                        f"panic_vector={moved['panic_vector']}, "
                        f"shell_alive={b'Version: 0.0.1' in response}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis native cursor stress passed: reports={reports}, "
          f"idle_growth={idle_growth}, mouse_growth={mouse_growth}")


if __name__ == "__main__":
    main()
