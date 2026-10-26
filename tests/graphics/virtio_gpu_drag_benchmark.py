#!/usr/bin/env python3
"""Measure visible VirtIO 2D window-drag response in a live QEMU boot.

The result includes QEMU monitor screenshot overhead and is an update-rate
probe, not a display refresh-rate measurement.
"""

import json
from pathlib import Path
from tempfile import TemporaryDirectory
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import capture_screen, monitor_command, read_until  # noqa: E402


def pixel(screen, x, y):
    width, _, data = screen
    offset = (y * width + x) * 3
    return tuple(data[offset:offset + 3])


def move(monitor, dx, dy):
    while dx or dy:
        step_x = max(-100, min(100, dx))
        step_y = max(-100, min(100, dy))
        monitor_command(str(monitor), f"mouse_move {step_x} {step_y}")
        dx -= step_x
        dy -= step_y
        time.sleep(0.08)


def main():
    qemu, firmware, iso, accel, output = sys.argv[1:6]
    iso = str(Path(iso).resolve())
    with TemporaryDirectory(prefix="australis-virtio-drag-") as directory:
        serial = Path(directory) / "serial.sock"
        monitor = Path(directory) / "monitor.sock"
        screenshot = Path(directory) / "screen.ppm"
        command = [
            qemu, "-machine", f"q35,accel={accel}", "-m", "256M",
            "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
            "-cdrom", iso, "-display", "none", "-net", "none",
            "-no-reboot", "-vga", "none", "-device", "virtio-vga,id=gpu0",
            "-device", "qemu-xhci,id=xhci0", "-device", "usb-kbd,bus=xhci0.0",
            "-device", "usb-mouse,bus=xhci0.0", "-serial",
            f"unix:{serial},server=on,wait=off", "-monitor",
            f"unix:{monitor},server=on,wait=off", "-device", "ich9-ahci,id=ahci0",
            "-drive", f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
            "-device", "ide-hd,drive=sata0,bus=ahci0.0",
        ]
        process = subprocess.Popen(
            command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
        )
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
                    raise AssertionError("desktop did not start")
                screen = capture_screen(str(monitor), screenshot, "gpu0")
                width, height, _ = screen
                if pixel(screen, 30, 100) != (203, 56, 48):
                    raise AssertionError("window A is not at its starting position")

                move(monitor, 100 - width // 2, 65 - height // 2)
                time.sleep(0.3)
                positioned = capture_screen(str(monitor), screenshot, "gpu0")
                if (pixel(positioned, 100, 69) != (255, 255, 255) or
                        pixel(positioned, 102, 69) != (16, 16, 16)):
                    raise AssertionError("cursor missed window A title bar")
                monitor_command(str(monitor), "mouse_button 1")
                time.sleep(0.35)
                read_until(connection, b"DBG: keyboard focus=1", 10, process)

                latencies = []
                try:
                    for step in range(4):
                        sample_x = 30 + step * 25
                        before = pixel(
                            capture_screen(str(monitor), screenshot, "gpu0"),
                            sample_x, 100,
                        )
                        started = time.monotonic()
                        monitor_command(str(monitor), "mouse_move 25 0")
                        deadline = started + 8
                        while True:
                            after = pixel(
                                capture_screen(str(monitor), screenshot, "gpu0"),
                                sample_x, 100,
                            )
                            if after != before:
                                break
                            if time.monotonic() >= deadline:
                                raise TimeoutError(f"drag step {step} did not render")
                            time.sleep(0.02)
                        latencies.append(time.monotonic() - started)
                        time.sleep(0.15)
                finally:
                    monitor_command(str(monitor), "mouse_button 0")

                result = {
                    "accelerator": accel,
                    "display": [width, height],
                    "drag_step_px": 25,
                    "latency_seconds": [round(value, 3) for value in latencies],
                    "mean_latency_seconds": round(sum(latencies) / len(latencies), 3),
                    "visible_updates_per_second": round(
                        len(latencies) / sum(latencies), 1
                    ),
                }
                destination = Path(output)
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text(json.dumps(result, indent=2) + "\n")
                print(json.dumps(result, indent=2))
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    main()
