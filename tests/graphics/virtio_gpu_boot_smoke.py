#!/usr/bin/env python3
"""Exercise VirtIO-GPU 2D scanout and the optional VirGL context probe."""

from pathlib import Path
from tempfile import TemporaryDirectory
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import capture_screen, monitor_command, read_until  # noqa: E402


def pixel(screen, x, y):
    width, height, pixels = screen
    offset = (y * width + x) * 3
    return tuple(pixels[offset:offset + 3])


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    oversized_mode = len(sys.argv) > 5 and sys.argv[5] == "oversized"
    use_gl = len(sys.argv) > 6 and sys.argv[5] == "gl"
    primary_vga = len(sys.argv) > 5 and sys.argv[5] == "vga"
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    iso = str(Path(iso).resolve())
    with TemporaryDirectory(prefix="australis-virtio-gpu-") as directory:
        serial = Path(directory) / "serial.sock"
        monitor = Path(directory) / "monitor.sock"
        screenshot = Path(directory) / "desktop.ppm"
        display = (f"egl-headless,rendernode={sys.argv[6]}"
                   if use_gl else "none")
        gpu = ("virtio-gpu-pci,id=gpu0,xres=1600,yres=900"
               if oversized_mode else
               "virtio-gpu-gl-pci,id=gpu0" if use_gl else
               "virtio-vga,id=gpu0" if primary_vga else
               "virtio-gpu-pci,id=gpu0")
        command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
                   f"if=pflash,format=raw,readonly=on,file={firmware}",
                   "-cdrom", iso, "-display", display, "-net", "none",
                   "-no-reboot", "-vga", "none" if primary_vga else "std",
                   "-device", gpu,
                   "-device", "qemu-xhci,id=xhci0",
                   "-device", "usb-kbd,bus=xhci0.0", "-device",
                   "usb-mouse,bus=xhci0.0", "-serial",
                   f"unix:{serial},server=on,wait=off", "-monitor",
                   f"unix:{monitor},server=on,wait=off"]
        if use_gl:
            command += ["-vnc", "none"]
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
                    raise TimeoutError("QEMU did not open its serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(serial))
                opening = read_until(connection, b"australis> ", 90, process)
                expected_backend = b"VirtIO-GPU native display active"
                if (b"VirtIO-GPU 2D probe passed" not in opening or
                        expected_backend not in opening or
                        b"System: display ready" not in opening):
                    raise AssertionError(f"GPU display boot failed: {opening[-3000:]!r}")
                if use_gl and (b"VirtIO-GPU VirGL context probe passed" not in opening or
                               b"VirtIO-GPU VirGL texture probe passed" not in opening or
                               b"VirtIO-GPU VirGL submission probe passed" not in opening or
                               b"VirtIO-GPU VirGL surface upload/readback passed" not in opening or
                               b"VirtIO-GPU VirGL clear/readback passed" not in opening or
                               b"VirtIO-GPU VirGL context active" not in opening or
                               b"VirtIO-GPU 2D/3D device reset recovery passed" not in opening or
                               b"Display: isolated GPU resource operations passed" not in opening or
                               b"Display: GPU tile composed to scanout" not in opening or
                               b"DisplayDemoA: GPU isolation passed" not in opening):
                    raise AssertionError(
                        f"VirGL context probe failed: {opening[-3000:]!r}")
                if use_gl:
                    connection.sendall(b"version\r")
                    reply = read_until(connection, b"australis> ", 20,
                                       process)
                    if b"Version: 0.0.1" not in reply:
                        raise AssertionError(
                            f"shell failed after VirGL probe: {reply[-2000:]!r}")
                    print(f"Australis {transport.upper()} VirGL context probe passed")
                    return
                scanout_cursor = (
                    b"VirtIO-GPU scanout cursor active" in opening)
                if not scanout_cursor:
                    raise AssertionError(
                        "native VirtIO-GPU boot did not activate scanout cursor")
                screen = capture_screen(str(monitor), screenshot, "gpu0")
                width, height, _ = screen
                if ((oversized_mode and (width, height) != (1280, 800)) or
                        width < 320 or height < 240 or
                        pixel(screen, 30, 100) != (203, 56, 48) or
                        pixel(screen, width // 3 + 20, 130) != (42, 104, 217) or
                        pixel(screen, 100, 10) != (17, 24, 32) or
                        pixel(screen, width // 2 + 2, height // 2 + 4) !=
                        (255, 255, 255)):
                    raise AssertionError(
                        f"scanout missed desktop: {width}x{height}, "
                        f"A={pixel(screen, 30, 100)}, "
                        f"B={pixel(screen, width // 3 + 20, 130)}, "
                        f"bar={pixel(screen, 100, 10)}")
                if not oversized_mode:
                    monitor_command(str(monitor), "mouse_move 30 -20")
                    read_until(connection,
                               b"VirtIO-GPU scanout cursor moved", 15,
                               process)
                    moved = capture_screen(str(monitor), screenshot, "gpu0")
                    if (pixel(moved, width // 2 + 32,
                              height // 2 - 16) != (255, 255, 255) or
                            pixel(moved, width // 2 + 2,
                                  height // 2 + 4) == (255, 255, 255)):
                        raise AssertionError(
                            "native scanout missed or did not restore cursor")
                    monitor_command(str(monitor), "mouse_button 1")
                    time.sleep(0.08)
                    monitor_command(str(monitor), "mouse_button 0")
                    routed = read_until(connection,
                                        b"DisplayDemoB: pointer down",
                                        15, process)
                    if b"DisplayDemoB: pointer up" not in routed:
                        read_until(connection, b"DisplayDemoB: pointer up",
                                   15, process)
                    time.sleep(0.2)
                    monitor_command(str(monitor), "sendkey m 50")
                    read_until(connection, b"Display: mode changed to 1024x768",
                               30, process)
                    deadline = time.monotonic() + 15
                    while time.monotonic() < deadline:
                        resized = capture_screen(str(monitor), screenshot,
                                                 "gpu0")
                        if (resized[0] == 1024 and resized[1] == 768 and
                                pixel(resized, 30, 100) == (203, 56, 48) and
                                pixel(resized, 1024 // 3 + 20, 130) ==
                                (42, 104, 217)):
                            break
                        time.sleep(0.1)
                    else:
                        raise AssertionError("native mode change missed desktop")
                    monitor_command(str(monitor), "sendkey m 50")
                    read_until(connection, b"Display: mode changed to 1280x800",
                               30, process)
                    deadline = time.monotonic() + 15
                    while time.monotonic() < deadline:
                        restored = capture_screen(str(monitor), screenshot,
                                                  "gpu0")
                        if (restored[0] == 1280 and restored[1] == 800 and
                                pixel(restored, 30, 100) == (203, 56, 48) and
                                pixel(restored, 1280 // 3 + 20, 130) ==
                                (42, 104, 217)):
                            break
                        time.sleep(0.1)
                    else:
                        raise AssertionError("native mode restore missed desktop")
                connection.sendall(b"version\r")
                reply = read_until(connection, b"australis> ", 20, process)
                if b"Version: 0.0.1" not in reply:
                    raise AssertionError(f"shell failed after GPU probe: {reply[-2000:]!r}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    backend = ("clamped native VirtIO-GPU" if oversized_mode else
               "VirGL-capable VirtIO-GPU" if use_gl else "native VirtIO-GPU")
    print(f"Australis {transport.upper()} {backend} desktop passed")


if __name__ == "__main__":
    main()
