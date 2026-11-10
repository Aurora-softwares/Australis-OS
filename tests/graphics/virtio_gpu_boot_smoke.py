#!/usr/bin/env python3
"""Exercise VirtIO-GPU 2D scanout and the optional VirGL context probe."""

from pathlib import Path
from tempfile import TemporaryDirectory
import select
import socket
import subprocess
import sys
import time
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import capture_screen, monitor_command, read_until  # noqa: E402


def pixel(screen, x, y):
    width, height, pixels = screen
    offset = (y * width + x) * 3
    return tuple(pixels[offset:offset + 3])

def capture_gpu_screen(path):
    subprocess.run(
        [
            "vncdo",
            "-s", "127.0.0.1::5907",
            "capture", str(path)
        ],
        check=True,
        timeout=10
    )

    with Image.open(path) as image:
        rgb = image.convert("RGB")
        return rgb.width, rgb.height, rgb.tobytes()


def gpu_cursor_position(screen):
    width, height, pixels = screen
    stride = width * 3
    marker = bytes((255, 255, 255, 16, 16, 16,
                    16, 16, 16, 255, 255, 255))
    for row in range(4, height - 16):
        start = row * stride
        found = pixels.find(marker, start, start + stride)
        if found >= 0 and (found - start) % 3 == 0:
            return (found - start) // 3, row - 4
    return None

def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    oversized_mode = len(sys.argv) > 5 and sys.argv[5] == "oversized"
    console_handoff = len(sys.argv) > 5 and sys.argv[5] == "console"
    use_gl = len(sys.argv) > 6 and sys.argv[5] == "gl"
    primary_vga = len(sys.argv) > 5 and sys.argv[5] == "vga"
    gpu_visual = len(sys.argv) > 7 and sys.argv[7] == "visual"
    gpu_live = len(sys.argv) > 7 and sys.argv[7] == "live"
    gpu_lowmem = len(sys.argv) > 7 and sys.argv[7] == "lowmem"
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    iso = str(Path(iso).resolve())
    with TemporaryDirectory(prefix="australis-virtio-gpu-") as directory:
        serial = Path(directory) / "serial.sock"
        monitor = Path(directory) / "monitor.sock"
        screenshot = Path(directory) / "desktop.ppm"
        live_screenshot = Path(directory) / "live.png"

        def capture_current():
            if gpu_live or gpu_lowmem:
                return capture_gpu_screen(live_screenshot)
            return capture_screen(str(monitor), screenshot, "gpu0")
        display = (f"egl-headless,rendernode={sys.argv[6]}"
                   if use_gl else "none")
        gpu = ("virtio-gpu-pci,id=gpu0,xres=1600,yres=900"
               if oversized_mode else
               "virtio-gpu-gl-pci,id=gpu0" if use_gl else
               "virtio-vga,id=gpu0" if primary_vga else
               "virtio-gpu-pci,id=gpu0")
        # Visual tests use VirtIO as the primary VGA-compatible GPU.
        if (gpu_visual or gpu_live or gpu_lowmem) and use_gl:
            gpu = "virtio-vga-gl,id=gpu0"
        memory = "512M" if gpu_live else "256M"
        command = [qemu, "-machine", "q35", "-m", memory, "-drive",
                   f"if=pflash,format=raw,readonly=on,file={firmware}",
                   "-cdrom", iso, "-display", display, "-net", "none",
                   "-no-reboot", "-vga", "none" if (primary_vga or gpu_visual or gpu_live or gpu_lowmem) else "std",
                   "-device", gpu,
                   "-device", "qemu-xhci,id=xhci0",
                   "-device", "usb-kbd,bus=xhci0.0", "-device",
                   "usb-mouse,bus=xhci0.0", "-serial",
                   f"unix:{serial},server=on,wait=off", "-monitor",
                   f"unix:{monitor},server=on,wait=off"]
        if use_gl:
            command += ["-vnc", "127.0.0.1:7"]
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
                if gpu_visual:
                    read_until(
                        connection, b"GPUVIS: PRESENTED", 90, process
                    )

                    gpu_path = Path("build/gpu-live-visual.png").resolve()
                    gpu_path.parent.mkdir(parents=True, exist_ok=True)

                    gpu_screen = capture_gpu_screen(gpu_path)

                    width, height, _ = gpu_screen

                    def near(actual, expected, tolerance=3):
                        return all(
                            abs(a - b) <= tolerance
                            for a, b in zip(actual, expected)
                        )

                    # GPU background instead of the software desktop topbar.
                    assert near(pixel(gpu_screen, 100, 10), (38, 56, 79))

                    # Rounded window A's titlebar and red close control.
                    assert near(pixel(gpu_screen, 32, 48), (229, 232, 237))
                    assert near(pixel(gpu_screen, 34, 63), (255, 95, 87))

                    # Window B is above A and has its own close control.
                    assert near(
                        pixel(gpu_screen, width // 3 + 14, 87),
                        (255, 95, 87)
                    )

                    read_until(
                        connection, b"GPUVIS: RESTORED", 30, process
                    )

                    software_path = Path("build/gpu-restored.png").resolve()
                    software_screen = capture_gpu_screen(software_path)

                    # The original desktop topbar must reappear.
                    assert near(
                        pixel(software_screen, 100, 10),
                        (17, 24, 32)
                    )

                    # Compare the whole desktop below the top bar. This
                    # probe does not draw the top bar, and the restored 2D
                    # scanout has the software cursor at the screen center.
                    assert gpu_screen[:2] == software_screen[:2]
                    gpu_pixels = gpu_screen[2]
                    software_pixels = software_screen[2]
                    for y in range(30, height):
                        spans = ((0, width),)
                        if height // 2 <= y < height // 2 + 20:
                            spans = ((0, width // 2),
                                     (width // 2 + 14, width))
                        for left, right in spans:
                            start = (y * width + left) * 3
                            end = (y * width + right) * 3
                            if gpu_pixels[start:end] != software_pixels[start:end]:
                                for x in range(left, right):
                                    actual = pixel(gpu_screen, x, y)
                                    expected = pixel(software_screen, x, y)
                                    if not near(actual, expected):
                                        raise AssertionError(
                                            "GPU/software mismatch at "
                                            f"({x}, {y}): {actual} != {expected}"
                                        )

                    print("GPU live visual scanout and restoration passed")
                    print(f"GPU screenshot: {gpu_path}")
                    print(f"Software screenshot: {software_path}")
                    return
                opening = read_until(connection, b"australis> ", 90, process)
                expected_backend = b"VirtIO-GPU native display active"
                if (b"VirtIO-GPU 2D probe passed" not in opening or
                        expected_backend not in opening or
                        b"System: display ready" not in opening):
                    raise AssertionError(f"GPU display boot failed: {opening[-3000:]!r}")
                if console_handoff:
                    before = capture_current()
                    if pixel(before, 100, 10) != (17, 24, 32):
                        raise AssertionError("selected GPU missed desktop before handoff")
                    connection.sendall(b"exit\r")
                    ended = read_until(connection, b"kmon> ", 30, process)
                    if b"Display stopped; COM1 active" not in ended:
                        raise AssertionError("display lease did not release")
                    after = capture_current()
                    if (after[:2] != before[:2] or
                            pixel(after, 100, 10) == (17, 24, 32) or
                            pixel(after, after[0] - 20, after[1] - 20) !=
                            (0, 0, 0) or
                            not any(pixel(after, x, y) == (255, 255, 255)
                                    for y in range(8, 48)
                                    for x in range(0, 256))):
                        raise AssertionError(
                            "recovery console did not use selected GPU scanout")
                    print("Australis selected VirtIO-GPU console handoff passed")
                    return
                if use_gl and (b"VirtIO-GPU VirGL context probe passed" not in opening or
                               b"VirtIO-GPU VirGL texture probe passed" not in opening or
                               b"VirtIO-GPU VirGL submission probe passed" not in opening or
                               b"VirtIO-GPU VirGL surface upload/readback passed" not in opening or
                               b"VirtIO-GPU VirGL clear/readback passed" not in opening or
                               b"VirtIO-GPU VirGL scanout probe passed" not in opening or
                               b"VirtIO-GPU VirGL blend state probe passed" not in opening or
                               b"VirtIO-GPU VirGL shader state probe passed" not in opening or
                               b"VirtIO-GPU VirGL alpha draw/readback passed" not in opening or
                               b"VirtIO-GPU VirGL textured alpha draw/readback passed" not in opening or
                               b"VirtIO-GPU VirGL context active" not in opening or
                               b"VirtIO-GPU 2D/3D device reset recovery passed" not in opening or
                               b"VirtIO-GPU VirGL sampler state probe passed" not in opening or
                               b"VirtIO-GPU VirGL UV shader linkage passed" not in opening or
                               b"VirtIO-GPU VirGL UV vertex layout passed" not in opening or
                               b"VirtIO-GPU VirGL UV pixels/readback passed" not in opening or
                               b"VirtIO-GPU VirGL positioned UV rectangle passed" not in opening or
                               b"VirtIO-GPU VirGL arbitrary UV rectangle passed" not in opening or
                               b"VirtIO-GPU VirGL multi-rectangle composition passed" not in opening or
                               b"VirtIO-GPU VirGL overlapping alpha composition passed" not in opening or
                               b"VirtIO-GPU VirGL persistent vertex lifecycle passed" not in opening or
                               b"VirtIO-GPU VirGL persistent vertex reuse passed" not in opening or
                               b"VirtIO-GPU VirGL independent window textures passed" not in opening or
                               b"VirtIO-GPU VirGL persistent sampler lifecycle passed" not in opening or
                               b"VirtIO-GPU VirGL persistent sampler drawing passed" not in opening or
                               b"VirtIO-GPU VirGL frame composer passed" not in opening or
                               b"VirtIO-GPU VirGL non-square viewport passed" not in opening or
                               b"VirtIO-GPU VirGL display-sized target passed" not in opening or
                               b"VirtIO-GPU VirGL full-frame scanout passed" not in opening or
                               b"VirtIO-GPU VirGL native composer setup passed" not in opening or
                               b"VirtIO-GPU VirGL owned window composition passed" not in opening or
                               b"VirtIO-GPU VirGL composed frame scanout passed" not in opening or
                               b"Display: GPU decorated windows passed" not in opening or
                               b"Display: GPU rounded decorations passed" not in opening or
                               b"Display: GPU frame submission passed" not in opening or
                               b"Display: GPU desktop composition passed" not in opening or
                               b"Display: GPU frame rectangles passed" not in opening or
                               b"Display: isolated GPU resource operations passed" not in opening or
                               b"Display: window-sized GPU texture passed" not in opening or
                               b"Display: two GPU-backed window contents ready" not in opening or
                               b"Display: GPU region blit passed" not in opening or
                               b"Display: GPU texture copy passed" not in opening or
                               b"Display: GPU tile composed to scanout" not in opening or
                               b"DisplayDemoA: GPU isolation passed" not in opening):
                    raise AssertionError(
                        f"VirGL context probe failed: {opening[-3000:]!r}")
                if gpu_lowmem:
                    marker = b"Display: GPU live deferred for available memory"
                    if marker not in opening:
                        read_until(connection, marker, 30, process)
                if use_gl and not gpu_live and not gpu_lowmem:
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
                deadline = time.monotonic() + 15
                while True:
                    screen = capture_current()
                    width, height, _ = screen
                    if pixel(screen, 100, 10) == (17, 24, 32):
                        break
                    if time.monotonic() >= deadline:
                        break
                    time.sleep(0.1)
                if ((oversized_mode and (width, height) != (1280, 800)) or width < 320 or height < 240 or pixel(screen, 30, 100) != (203, 56, 48) or pixel(screen, width // 3 + 20, 130) != (42, 104, 217) or pixel(screen, 100, 10) != (17, 24, 32) or pixel(screen, width // 2, height // 2 + 4) != (255, 255, 255) or pixel(screen, width // 2 + 2, height // 2 + 4) != (16, 16, 16)):
                    raise AssertionError(
                        f"scanout missed desktop: {width}x{height}, "
                        f"A={pixel(screen, 30, 100)}, "
                        f"B={pixel(screen, width // 3 + 20, 130)}, "
                        f"bar={pixel(screen, 100, 10)}")
                if not oversized_mode:
                    monitor_command(str(monitor), "mouse_move 30 -20")
                    cursor_reply = read_until(
                        connection, b"VirtIO-GPU scanout cursor moved",
                        15, process)
                    if (gpu_live and
                            b"Display: live GPU composition active" not in
                            opening + cursor_reply):
                        read_until(connection,
                                   b"Display: live GPU composition active",
                                   30, process)

                    # Wait for the cursor to become visible at its new position.
                    old_x = width // 2
                    old_y = height // 2

                    new_x = old_x + 30
                    new_y = old_y - 20

                    deadline = time.monotonic() + 5

                    while True:
                        moved = capture_current()

                        outline = pixel(moved, new_x, new_y + 4)
                        fill = pixel(moved, new_x + 2, new_y + 4)
                        old_outline = pixel(moved, old_x, old_y + 4)

                        cursor_correct = (
                            outline == (255, 255, 255)
                            and fill == (16, 16, 16)
                        )
                        old_restored = old_outline != (255, 255, 255)

                        if cursor_correct and old_restored:
                            break

                        if time.monotonic() >= deadline:
                            # Preserve the failing screenshot for inspection.
                            debug_path = Path("build/virtio-cursor-after.ppm")
                            debug_path.parent.mkdir(parents=True, exist_ok=True)
                            debug_path.write_bytes(
                                (live_screenshot if gpu_live else screenshot).read_bytes())

                            # Search for cursor-shaped pixels near the expected location.
                            candidates = []

                            for cy in range(max(0, new_y - 64),
                                            min(height - 16, new_y + 65)):
                                for cx in range(max(0, new_x - 64),
                                                min(width - 14, new_x + 65)):
                                    if (
                                        pixel(moved, cx, cy + 4) == (255, 255, 255)
                                        and pixel(moved, cx + 2, cy + 4) == (16, 16, 16)
                                        and pixel(moved, cx + 5, cy + 4) == (255, 255, 255)
                                    ):
                                        candidates.append((cx, cy))

                                    if len(candidates) >= 8:
                                        break

                                if len(candidates) >= 8:
                                    break

                            raise AssertionError(
                                "VirtIO cursor move failed: "
                                f"expected=({new_x}, {new_y}), "
                                f"outline={outline}, "
                                f"fill={fill}, "
                                f"old_outline={old_outline}, "
                                f"nearby_cursor_candidates={candidates}, "
                                f"screenshot={debug_path}"
                            )

                        time.sleep(0.1)

                    # Press and keep the button held until Australis
                    # has actually processed the button-down event.
                    monitor_command(str(monitor), "mouse_button 1")

                    press_started = time.monotonic()

                    try:
                        routed = read_until(
                            connection,
                            b"DisplayDemoB: pointer down",
                            30,
                            process,
                        )
                        # Confirm that Window B received keyboard ownership
                        # before attempting the mode-switch shortcut.
                        print(
                            "POINTER AND FOCUS LOG:",
                            repr(routed[-4000:]),
                            flush=True,
                        )

                        expected_capture = (
                            b"DBG: keyboard focus=2 capture=1 result=0"
                        )

                        if expected_capture not in routed:
                            raise AssertionError(
                                "Window B received pointer-down, but successful "
                                "keyboard capture was not confirmed.\n"
                                f"Serial output: {routed[-4000:]!r}"
                            )
                        print(
                            "POINTER DOWN SERIAL:",
                            routed[-2000:].decode(errors="replace"),
                            flush=True,
                        )
                    finally:
                        # Always release the mouse button, including on failure.
                        monitor_command(str(monitor), "mouse_button 0")

                    press_latency = time.monotonic() - press_started

                    print(f"VirtIO pointer-down latency: {press_latency:.3f}s")

                    # Check that the release reaches the same client.
                    if b"DisplayDemoB: pointer up" not in routed:
                        released = read_until(
                            connection,
                            b"DisplayDemoB: pointer up",
                            30,
                            process,
                        )

                        print(
                            "POINTER UP SERIAL:",
                            released[-2000:].decode(errors="replace"),
                            flush=True,
                        )

                    time.sleep(0.2)
                    if gpu_live:
                        live_cursor_x = new_x
                        live_cursor_y = new_y

                        def move_to(target_x, target_y):
                            nonlocal live_cursor_x, live_cursor_y
                            dx = target_x - live_cursor_x
                            dy = target_y - live_cursor_y
                            while dx or dy:
                                step_x = max(-100, min(100, dx))
                                step_y = max(-100, min(100, dy))
                                monitor_command(str(monitor),
                                                f"mouse_move {step_x} {step_y}")
                                dx -= step_x
                                dy -= step_y
                                time.sleep(0.3)
                            observed = []
                            deadline = time.monotonic() + 15
                            while time.monotonic() < deadline:
                                current = gpu_cursor_position(capture_current())
                                observed.append(current)
                                if current == (target_x, target_y):
                                    live_cursor_x = target_x
                                    live_cursor_y = target_y
                                    return
                                time.sleep(0.2)
                            debug_path = Path("build/gpu-live-interaction-failure.png")
                            debug_path.write_bytes(live_screenshot.read_bytes())
                            serial_tail = b""
                            serial_deadline = time.monotonic() + 2
                            while time.monotonic() < serial_deadline:
                                if not select.select([connection], [], [], 0.1)[0]:
                                    continue
                                serial_tail += connection.recv(8192)
                            raise AssertionError(
                                f"GPU cursor missed ({target_x},{target_y}): "
                                f"{observed[-12:]}; screenshot={debug_path}; "
                                f"serial={serial_tail[-4000:]!r}")

                        def wait_live_pixel(x, y, expected, seconds=15):
                            deadline = time.monotonic() + seconds
                            actual = None
                            while time.monotonic() < deadline:
                                actual = pixel(capture_current(), x, y)
                                if actual == expected:
                                    return
                                time.sleep(0.2)
                            debug_path = Path("build/gpu-live-interaction-failure.png")
                            debug_path.write_bytes(live_screenshot.read_bytes())
                            serial_tail = b""
                            while select.select([connection], [], [], 0)[0]:
                                serial_tail += connection.recv(8192)
                            raise AssertionError(
                                f"GPU pixel ({x},{y})={actual}, "
                                f"expected {expected}; screenshot={debug_path}; "
                                f"serial={serial_tail[-2000:]!r}")

                        def click(expected=None):
                            monitor_command(str(monitor), "mouse_button 1")
                            monitor_command(str(monitor), "mouse_move 1 0")
                            if expected is None:
                                time.sleep(1.0)
                            else:
                                read_until(connection, expected, 20, process)
                            monitor_command(str(monitor), "mouse_button 0")
                            monitor_command(str(monitor), "mouse_move -1 0")
                            time.sleep(1.0)

                        # Raise A, move it across B, and resize it while
                        # the GPU-composed scanout remains selected.
                        move_to(200, 200)
                        click()
                        move_to(120, 60)
                        monitor_command(str(monitor), "mouse_button 1")
                        time.sleep(0.4)
                        move_to(220, 100)
                        monitor_command(str(monitor), "mouse_button 0")
                        time.sleep(0.5)
                        wait_live_pixel(30, 100, (38, 56, 79))
                        wait_live_pixel(500, 150, (203, 56, 48))
                        move_to(725, 483)
                        monitor_command(str(monitor), "mouse_button 1")
                        time.sleep(0.4)
                        move_to(805, 543)
                        monitor_command(str(monitor), "mouse_button 0")
                        time.sleep(0.5)
                        wait_live_pixel(770, 510, (203, 56, 48))

                        # Maximized content and controls use the same bounds
                        # and hit regions as the software desktop.
                        move_to(173, 101)
                        click(b"Display: window maximized")
                        wait_live_pixel(100, 10, (0, 0, 0))
                        wait_live_pixel(30, 100, (203, 56, 48))
                        move_to(53, 14)
                        click(b"Display: window restored")
                        wait_live_pixel(100, 10, (17, 24, 32))
                        wait_live_pixel(30, 100, (38, 56, 79))
                        move_to(900, 85)
                        click(b"Display: stack changed to 2")
                        wait_live_pixel(500, 150, (42, 104, 217))
                        move_to(width - 80, height - 100)
                        monitor_command(str(monitor), "mouse_move 100 100")
                        time.sleep(0.4)
                        monitor_command(str(monitor), "mouse_move 100 100")
                        wait_live_pixel(width - 14, height - 20,
                                        (255, 255, 255))
                        time.sleep(2)
                        wait_live_pixel(500, 150, (42, 104, 217))
                        print("Australis live GPU move/resize/stack/max/edge passed")
                    monitor_command(str(monitor), "sendkey m 50")
                    try:
                        read_until(connection,
                                   b"Display: mode changed to 1024x768",
                                   30, process)
                    except TimeoutError:
                        if gpu_live:
                            capture_current()
                            Path("build/gpu-live-mode-failure.png").write_bytes(
                                live_screenshot.read_bytes())
                        raise
                    deadline = time.monotonic() + 15
                    while time.monotonic() < deadline:
                        resized = capture_current()
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
                        restored = capture_current()
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
        except AssertionError as failure:
            process.terminate()
            try:
                _, stderr = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                _, stderr = process.communicate()
            raise AssertionError(
                f"{failure}\nQEMU stderr: {stderr[-4000:].decode(errors='replace')}") from failure
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
