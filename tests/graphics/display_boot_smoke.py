#!/usr/bin/env python3
"""Verify the AUEX display service, two clients, and the serial shell in QEMU."""

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
    if x < 0 or y < 0 or x >= width or y >= height:
        raise AssertionError("pixel sample outside display")
    offset = (y * width + x) * 3
    return tuple(pixels[offset:offset + 3])


def wait_pixel(monitor, screenshot, x, y, expected, seconds=10):
    deadline = time.monotonic() + seconds
    seen = None
    while time.monotonic() < deadline:
        screen = capture_screen(str(monitor), screenshot)
        seen = pixel(screen, x, y)
        if seen == expected:
            return screen
        time.sleep(0.1)
    raise AssertionError(
        f"pixel ({x},{y}) remained {seen}, expected {expected}; "
        f"bar={pixel(screen, 100, 10)}, A={pixel(screen, 130, 140)}")


def move_mouse(monitor, dx, dy):
    while dx or dy:
        step_x = max(-100, min(100, dx))
        step_y = max(-100, min(100, dy))
        monitor_command(str(monitor), f"mouse_move {step_x} {step_y}")
        dx -= step_x
        dy -= step_y
        time.sleep(0.08)


def click_mouse(monitor):
    monitor_command(str(monitor), "mouse_button 1")
    time.sleep(0.08)
    monitor_command(str(monitor), "mouse_button 0")


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    iso = str(Path(iso).resolve())
    with TemporaryDirectory(prefix="australis-display-") as directory:
        serial = Path(directory) / "serial.sock"
        monitor = Path(directory) / "monitor.sock"
        screenshot = Path(directory) / "display.ppm"
        command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
                   f"if=pflash,format=raw,readonly=on,file={firmware}",
                   "-cdrom", iso, "-display", "none", "-net", "none",
                   "-no-reboot", "-device", "qemu-xhci,id=xhci0",
                   "-device", "usb-kbd,bus=xhci0.0",
                   "-device", "usb-mouse,bus=xhci0.0", "-serial",
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
                if (b"Display: two owned buffers completed and released" not in opening or
                        b"Display: two client windows composed" not in opening or
                        b"Display: cross-window denial and close/reopen verified" not in opening or
                        b"System: display ready" not in opening):
                    raise AssertionError(f"display service did not start: {opening[-2500:]!r}")
                screen = capture_screen(str(monitor), screenshot)
                width, height, _ = screen
                if (width < 320 or height < 240 or
                        pixel(screen, 30, 100) != (203, 56, 48) or
                        pixel(screen, width // 3 + 20, 130) != (42, 104, 217) or
                        pixel(screen, 100, 10) != (17, 24, 32) or
                        pixel(screen, 20, 48) != (38, 56, 79) or
                        pixel(screen, 350, 200) != (243, 165, 82) or
                        pixel(screen, 600, 210) != (112, 205, 249) or
                        pixel(screen, 200, 200) != (203, 56, 48) or
                        pixel(screen, 760, 210) != (42, 104, 217)):
                    raise AssertionError(
                        f"two windows not composed: {width}x{height}, "
                        f"A={pixel(screen, 30, 100)}, "
                        f"B={pixel(screen, width // 3 + 20, 130)}, "
                        f"bar={pixel(screen, 100, 10)}")
                old_x, old_y = width // 2, height // 2
                if pixel(screen, old_x + 2, old_y + 4) != (255, 255, 255):
                    raise AssertionError("initial software cursor is not visible")
                monitor_command(str(monitor), "mouse_move 30 -20")
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    time.sleep(0.1)
                    moved = capture_screen(str(monitor), screenshot)
                    if pixel(moved, old_x + 32, old_y - 16) == (255, 255, 255):
                        break
                else:
					connection.settimeout(0.25)
					serial_tail = bytearray()

					for _ in range(32):
						try:
							chunk = connection.recv(4096)
						except socket.timeout:
							break

						if not chunk:
							break

						serial_tail.extend(chunk)

					connection.settimeout(None)

					print(
						"DISPLAY SERIAL AFTER MOUSE MOVEMENT:\n"
						+ serial_tail[-6000:].decode(errors="replace"),
						flush=True,
					)
                    raise AssertionError(
                        "USB mouse did not move the software cursor: "
                        f"old={pixel(moved, old_x + 2, old_y + 4)}, "
                        f"target={pixel(moved, old_x + 32, old_y - 16)}, "
                        f"background={pixel(moved, old_x + 38, old_y - 16)}")
                if pixel(moved, old_x + 2, old_y + 4) != (42, 104, 217):
                    raise AssertionError("cursor movement did not restore the covered window")
                click_mouse(monitor)
                routed = read_until(connection, b"DisplayDemoB: pointer down",
                                    15, process)
                if b"DisplayDemoA: pointer down" in routed:
                    raise AssertionError("top window pointer event reached client A")
                wait_pixel(monitor, screenshot, width // 3 + 100, 80,
                           (125, 167, 203))
                monitor_command(str(monitor), "sendkey b 50")
                routed = read_until(connection, b"DisplayDemoB: key", 15, process)
                if b"DisplayDemoA: key" in routed:
                    raise AssertionError("focused key reached client A")
                wait_pixel(monitor, screenshot, width // 3 + 20, 130,
                           (240, 211, 62))
                if pixel(capture_screen(str(monitor), screenshot), 30, 100) != (
                        203, 56, 48):
                    raise AssertionError("B update damaged A window")
                cursor_x, cursor_y = old_x + 30, old_y - 20
                move_mouse(monitor, 200 - cursor_x, 200 - cursor_y)
                cursor_x, cursor_y = 200, 200
                wait_pixel(monitor, screenshot, 202, 204, (255, 255, 255))
                click_mouse(monitor)
                routed = read_until(connection, b"DisplayDemoA: pointer down",
                                    15, process)
                if b"DisplayDemoB: pointer down" in routed:
                    raise AssertionError("A-only hit reached client B")
                if b"DisplayDemoA: pointer up" not in routed:
                    read_until(connection, b"DisplayDemoA: pointer up", 15, process)
                wait_pixel(monitor, screenshot, 100, 55, (125, 167, 203))
                wait_pixel(monitor, screenshot, 800, 80,
                           (199, 206, 214))
                monitor_command(str(monitor), "sendkey a 50")
                routed = read_until(connection, b"DisplayDemoA: key", 15, process)
                if b"DisplayDemoB: key" in routed:
                    raise AssertionError("focused key reached client B")
                wait_pixel(monitor, screenshot, 30, 100, (20, 200, 75))
                if pixel(capture_screen(str(monitor), screenshot),
                         760, 210) != (42, 104, 217):
                    raise AssertionError("A update damaged B-only content")
                overlap_x = width // 3 + 60
                monitor_command(str(monitor), "mouse_button 1")
                time.sleep(0.08)
                move_mouse(monitor, overlap_x - cursor_x, 0)
                cursor_x = overlap_x
                wait_pixel(monitor, screenshot, cursor_x + 2, cursor_y + 4,
                           (255, 255, 255))
                monitor_command(str(monitor), "mouse_button 0")
                routed = read_until(connection, b"DisplayDemoA: pointer up",
                                    15, process)
                if (b"DisplayDemoA: pointer move" not in routed or
                        b"DisplayDemoB: pointer move" in routed):
                    raise AssertionError("captured A drag reached the wrong client")
                click_mouse(monitor)
                routed = read_until(connection, b"DisplayDemoA: pointer down",
                                    15, process)
                if b"DisplayDemoB: pointer down" in routed:
                    raise AssertionError("raised A window lost the overlap hit")
                move_mouse(monitor, 760 - cursor_x, 0)
                cursor_x = 760
                wait_pixel(monitor, screenshot, cursor_x + 2, cursor_y + 4,
                           (255, 255, 255))
                click_mouse(monitor)
                routed = read_until(connection, b"DisplayDemoB: pointer down",
                                    15, process)
                if b"DisplayDemoA: pointer down" in routed:
                    raise AssertionError("B-only hit reached client A")
                wait_pixel(monitor, screenshot, 500, 150, (240, 211, 62))
                move_mouse(monitor, width - 30 - cursor_x,
                           height - 30 - cursor_y)
                cursor_x, cursor_y = width - 30, height - 30
                wait_pixel(monitor, screenshot, cursor_x + 2, cursor_y + 4,
                           (255, 255, 255))
                click_mouse(monitor)
                wait_pixel(monitor, screenshot, width // 3 + 100, 80,
                           (199, 206, 214))
                for key in "version":
                    monitor_command(str(monitor), f"sendkey {key} 20")
                    time.sleep(0.04)
                monitor_command(str(monitor), "sendkey ret 20")
                typed = read_until(connection, b"australis> ", 20, process)
                if b"Version: 0.0.1" not in typed:
                    raise AssertionError("USB keyboard did not return to serial shell")
                connection.sendall(b"version\r")
                reply = read_until(connection, b"australis> ", 20, process)
                if b"Version: 0.0.1" not in reply:
                    raise AssertionError(
                        f"serial shell stopped during display ownership: {reply[-1000:]!r}")
                move_mouse(monitor, 120 - cursor_x, 60 - cursor_y)
                cursor_x, cursor_y = 120, 60
                wait_pixel(monitor, screenshot, 122, 64, (255, 255, 255))
                monitor_command(str(monitor), "mouse_button 1")
                move_mouse(monitor, 100, 40)
                cursor_x, cursor_y = 220, 100
                monitor_command(str(monitor), "mouse_button 0")
                time.sleep(0.2)
                wait_pixel(monitor, screenshot, 130, 140, (20, 200, 75))
                wait_pixel(monitor, screenshot, 30, 100, (38, 56, 79))
                wait_pixel(monitor, screenshot, 500, 150, (203, 56, 48))
                move_mouse(monitor, 725 - cursor_x, 483 - cursor_y)
                cursor_x, cursor_y = 725, 483
                wait_pixel(monitor, screenshot, 727, 487, (255, 255, 255))
                monitor_command(str(monitor), "mouse_button 1")
                # Keep the press visible to the guest before sending motion;
                # USB reports can otherwise merge while a redraw is active.
                time.sleep(0.3)
                move_mouse(monitor, 80, 60)
                cursor_x, cursor_y = 805, 543
                time.sleep(0.3)
                monitor_command(str(monitor), "mouse_button 0")
                time.sleep(0.2)
                wait_pixel(monitor, screenshot, 770, 510, (203, 56, 48))
                move_mouse(monitor, width // 3 + 53 - cursor_x,
                           85 - cursor_y)
                cursor_x, cursor_y = width // 3 + 53, 85
                wait_pixel(monitor, screenshot, cursor_x + 2, cursor_y + 4,
                           (255, 255, 255))
                click_mouse(monitor)
                wait_pixel(monitor, screenshot, 100, 10, (0, 0, 0))
                wait_pixel(monitor, screenshot, 30, 100, (240, 211, 62))
                move_mouse(monitor, 53 - cursor_x, 14 - cursor_y)
                cursor_x, cursor_y = 53, 14
                click_mouse(monitor)
                wait_pixel(monitor, screenshot, 100, 10, (17, 24, 32))
                wait_pixel(monitor, screenshot, 500, 150, (240, 211, 62))
                move_mouse(monitor, width // 3 + 33 - cursor_x,
                           85 - cursor_y)
                cursor_x, cursor_y = width // 3 + 33, 85
                click_mouse(monitor)
                wait_pixel(monitor, screenshot, 500, 150, (203, 56, 48))
                wait_pixel(monitor, screenshot, width - 30, 16,
                           (97, 112, 128))
                move_mouse(monitor, width - 28 - cursor_x,
                           16 - cursor_y)
                cursor_x, cursor_y = width - 28, 16
                click_mouse(monitor)
                try:
                    wait_pixel(monitor, screenshot, 500, 150,
                               (240, 211, 62))
                except AssertionError as error:
                    connection.settimeout(0.2)
                    try:
                        serial_tail = connection.recv(8192)
                    except socket.timeout:
                        serial_tail = b""
                    connection.settimeout(None)
                    connection.sendall(b"exit\r")
                    try:
                        serial_tail += read_until(connection, b"kmon> ",
                                                  15, process)
                    except (AssertionError, TimeoutError, OSError):
                        pass
                    raise AssertionError(
                        f"{error}; serial={serial_tail[-3000:]!r}") from error
                move_mouse(monitor, 137 - cursor_x, 105 - cursor_y)
                cursor_x, cursor_y = 137, 105
                wait_pixel(monitor, screenshot, 131, 99, (255, 255, 255))
                click_mouse(monitor)
                wait_pixel(monitor, screenshot, 150, 150, (38, 56, 79))
                move_mouse(monitor, width - 30 - cursor_x,
                           height - 30 - cursor_y)
                cursor_x, cursor_y = width - 30, height - 30
                click_mouse(monitor)
                for index in range(96):
                    delta = 80 if index % 2 == 0 else -80
                    monitor_command(str(monitor), f"mouse_move {delta} 0")
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    stressed = capture_screen(str(monitor), screenshot)
                    if (pixel(stressed, 100, 10) != (17, 24, 32) or
                            pixel(stressed, 30, 100) != (38, 56, 79) or
                            pixel(stressed, width // 3 + 20, 130) !=
                            (240, 211, 62)):
                        raise AssertionError("mouse burst corrupted or lost the display")
                    time.sleep(0.1)
                connection.sendall(b"version\r")
                reply = read_until(connection, b"australis> ", 20, process)
                if b"Version: 0.0.1" not in reply:
                    raise AssertionError("serial shell stopped after mouse burst")
                connection.sendall(b"exit\r")
                ended = read_until(connection, b"kmon> ", 30, process)
                if b"System session ended; entering KMon." not in ended:
                    raise AssertionError(f"display session did not cleanly end: {ended[-1000:]!r}")
                if (b"Display stopped; COM1 active" not in ended or
                        b"\x1b[2J" in ended):
                    raise AssertionError("display release erased serial output")
                recovered = capture_screen(str(monitor), screenshot)
                if pixel(recovered, 100, 10) == (17, 24, 32):
                    raise AssertionError("display lease did not restore framebuffer console")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} display service and two clients passed")


if __name__ == "__main__":
    main()
