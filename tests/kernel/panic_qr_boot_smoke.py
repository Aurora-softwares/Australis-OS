
#!/usr/bin/env python3
"""Validate Hydrogen's QR encoder without causing a kernel panic."""

import hashlib
import os
import socket
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[1] / "console")
)

from serial_boot_smoke import (
    PROMPT,
    capture_record,
    capture_screen,
    monitor_command,
)

EXPECTED_PAYLOAD = (
    "AU1:00:"
    + ":".join(["0000000000000000"] * 4)
)

EXPECTED_SHA256 = (
    "d0de6f9c5af567aadabcb0652c6f21ce"
    "9163afa4b274256a9d8615a001e64e06"
)


def validate_qr(record, memory_path):
    entry = record["panic_qr_entry"]
    scratch = record["panic_qr_scratch"]

    if entry == 0:
        raise AssertionError("Hydrogen panic entry is missing")

    if scratch < 4096 or scratch % 4096 != 0:
        raise AssertionError(
            f"Invalid QR scratch address: {scratch:#x}"
        )

    with open(memory_path, "rb") as memory:
        memory.seek(scratch)
        page = memory.read(4096)

    if len(page) != 4096:
        raise AssertionError("Incomplete QR scratch page")

    marker = struct.unpack_from("<I", page, 1904)[0]
    result = struct.unpack_from("<I", page, 1908)[0]

    print(f"Panic entry:   {entry:#x}")
    print(f"Scratch page:  {scratch:#x}")
    print(f"QR marker:     {marker:#x}")
    print(f"QR result:     {result}")

    if marker != 0x51525354:
        raise AssertionError(
            "QR self-test did not run in Debug mode"
        )

    payload = page[:74].decode("ascii")

    print(f"QR payload:    {payload}")

    if payload != EXPECTED_PAYLOAD:
        raise AssertionError(
            "QR payload differs from expected boot-time data"
        )

    # Extract the 29x29 matrix.
    matrix = page[192:192 + 841]

    if len(matrix) != 841:
        raise AssertionError("Incomplete QR matrix")

    if any(value not in (0, 1) for value in matrix):
        raise AssertionError("Invalid QR module values")

    black = sum(matrix)
    digest = hashlib.sha256(matrix).hexdigest()

    print(f"QR dimensions: 29 x 29")
    print(f"Black modules: {black}")
    print(f"SHA256:        {digest}")

    if black != 432:
        raise AssertionError(
            f"Unexpected black-module count: {black}"
        )

    if digest != EXPECTED_SHA256:
        raise AssertionError(
            f"QR matrix mismatch (result={result})"
        )

    # Export a viewable image with a four-module quiet zone.
    # Standard PGM image format; no third-party dependencies.
    scale = 8
    module_size = 29
    image_size = (module_size + 8) * scale
    pixels = bytearray([255] * (image_size * image_size))

    for y in range(module_size):
        for x in range(module_size):
            if matrix[y * module_size + x] == 1:
                for py in range(scale):
                    for px in range(scale):
                        xx = (x + 4) * scale + px
                        yy = (y + 4) * scale + py
                        pixels[yy * image_size + xx] = 0

    output = Path("build/panic-qr-debug.pgm")
    output.parent.mkdir(parents=True, exist_ok=True)

    with output.open("wb") as image:
        image.write(
            f"P5\n{image_size} {image_size}\n255\n".encode()
        )
        image.write(pixels)

    print(f"QR image:      {output}")
    print("Hydrogen QR matrix validation PASSED")



def validate_qr_framebuffer(record, memory_path, monitor_path):
    scratch = record["panic_qr_scratch"]

    # Read the framebuffer-rendering result and the
    # actual QR matrix produced by Hydrogen.
    with open(memory_path, "rb") as memory:
        memory.seek(scratch + 1912)
        draw_result = struct.unpack("<I", memory.read(4))[0]

        memory.seek(scratch + 192)
        matrix = memory.read(841)

    print(f"QR draw result: {draw_result}")

    if draw_result != 1:
        raise AssertionError(
            "Hydrogen did not draw the QR to the framebuffer"
        )

    # Capture the real display through QEMU.
    screenshot = Path("build/panic-qr-framebuffer.ppm")
    screenshot.parent.mkdir(parents=True, exist_ok=True)

    width, height, pixels = capture_screen(
        monitor_path, str(screenshot)
    )

    scale = 6
    side = 37 * scale
    origin_x = width - side - 16
    origin_y = 24

    if origin_x < 512 or origin_y + side > height:
        raise AssertionError(
            f"QR does not fit the framebuffer: {width}x{height}"
        )

    # Compare all 222x222 pixels, including the
    # mandatory four-module white quiet zone.
    for my in range(37):
        for mx in range(37):
            black = False

            if 4 <= mx < 33 and 4 <= my < 33:
                index = (my - 4) * 29 + (mx - 4)
                black = matrix[index] == 1

            expected = (
                b"\x00\x00\x00" if black else b"\xff\xff\xff"
            ) * scale

            for py in range(scale):
                x = origin_x + mx * scale
                y = origin_y + my * scale + py

                offset = (y * width + x) * 3
                actual = pixels[offset:offset + scale * 3]

                if actual != expected:
                    raise AssertionError(
                        f"QR framebuffer mismatch at "
                        f"module ({mx}, {my}), pixel row {py}. "
                        f"Screenshot: {screenshot}"
                    )

    print(f"Framebuffer:   {width} x {height}")
    print(f"QR position:   ({origin_x}, {origin_y})")
    print(f"QR size:       {side} x {side}")
    print(f"QR screenshot: {screenshot}")
    print("Hydrogen QR framebuffer validation PASSED")



def main():
    qemu, firmware, iso = sys.argv[1:4]

    with tempfile.TemporaryDirectory(
        prefix="australis-qr-"
    ) as temporary:

        serial_path = os.path.join(temporary, "serial.sock")
        monitor_path = os.path.join(temporary, "monitor.sock")
        memory_path = os.path.join(temporary, "ram.bin")

        command = [
            qemu,
            "-machine", "q35",
            "-m", "256M",
            "-drive",
            f"if=pflash,format=raw,readonly=on,file={firmware}",
            "-cdrom", iso,
            "-device", "ich9-ahci,id=ahci0",
            "-drive",
            f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
            "-device", "ide-hd,drive=sata0,bus=ahci0.0",
            "-display", "none",
            "-no-reboot",
            "-net", "none",
            "-monitor",
            f"unix:{monitor_path},server=on,wait=off",
            "-serial",
            f"unix:{serial_path},server=on,wait=off",
        ]

        process = subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )

        try:
            deadline = time.monotonic() + 10

            while not os.path.exists(serial_path):
                if process.poll() is not None:
                    raise RuntimeError(
                        process.stderr.read().decode(
                            errors="replace"
                        )
                    )
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU serial socket missing")
                time.sleep(0.05)

            with socket.socket(socket.AF_UNIX) as serial:
                serial.connect(serial_path)
                serial.settimeout(0.2)

                received = bytearray()
                deadline = time.monotonic() + 60
                last_key = 0.0

                # Select Debug mode at the UEFI boot menu.
                while PROMPT not in received:
                    if process.poll() is not None:
                        raise RuntimeError(
                            "QEMU exited before Debug KMon"
                        )

                    if time.monotonic() >= deadline:
                        raise TimeoutError(
                            f"Debug boot timed out: {received[-400:]!r}"
                        )

                    if (
                        b"[BOOT:DEBUG] AUKR kernel validated." not in received
                        and time.monotonic() - last_key >= 1.0
                    ):
                        monitor_command(
                            monitor_path, "sendkey d 70"
                        )
                        last_key = time.monotonic()

                    try:
                        received.extend(serial.recv(4096))
                    except socket.timeout:
                        pass

                if b"[BOOT:DEBUG] AUKR kernel validated." not in received:
                    raise AssertionError(
                        "System did not enter Debug boot mode. "
                        f"Serial output: {received[-800:]!r}"
                    )

                record = capture_record(
                    monitor_path, memory_path
                )

                validate_qr(record, memory_path)
                validate_qr_framebuffer(
                    record, memory_path, monitor_path
                )

        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()

            if process.stderr is not None:
                process.stderr.close()


if __name__ == "__main__":
    main()
