#!/usr/bin/env python3
"""Exercise the live kernel shell over COM1 with an AHCI or NVMe HyFS root."""

from pathlib import Path
import mmap
import os
import re
import socket
import struct
import subprocess
import sys
import tempfile
import time


PROMPT = b"kmon> "
BANNER = b"kmon serial console ready. Type help.\r\n"
VERSION = b"version: 0.0.1\r\n"


def monitor_command(path, command):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(5)
        connection.connect(path)
        response = b""
        while not response.endswith(b"(qemu) "):
            response += connection.recv(4096)
        connection.sendall((command + "\n").encode())
        response = b""
        while not response.endswith(b"(qemu) "):
            response += connection.recv(4096)
        if b"Error" in response or b"invalid" in response:
            raise RuntimeError(f"QEMU monitor rejected {command!r}: {response!r}")
        return response


def kernel_record(path):
    with open(path, "rb") as image:
        memory = mmap.mmap(image.fileno(), 0, access=mmap.ACCESS_READ)
        position = 0
        while True:
            position = memory.find(b"AUBI", position)
            if position < 0:
                return None
            if struct.unpack_from("<I", memory, position + 4)[0] == 7:
                return {
                    "state": struct.unpack_from("<I", memory, position + 36)[0],
                    "allocator_next": struct.unpack_from("<Q", memory, position + 40)[0],
                    "heap_next": struct.unpack_from("<Q", memory, position + 88)[0],
                    "heap_end": struct.unpack_from("<Q", memory, position + 96)[0],
                    "exception": struct.unpack_from("<I", memory, position + 188)[0],
                    "last_vector": struct.unpack_from("<I", memory, position + 184)[0],
                    "serial_flags": struct.unpack_from("<I", memory, position + 1140)[0],
                    "command_count": struct.unpack_from("<I", memory, position + 1144)[0],
                    "serial_irqs": struct.unpack_from("<I", memory, position + 1148)[0],
                    "memory_error": struct.unpack_from("<I", memory, position + 1160)[0],
                    "mapping_error": struct.unpack_from("<I", memory, position + 1164)[0],
                    "transient_floor": struct.unpack_from("<Q", memory, position + 1152)[0],
                    "free_page_head": struct.unpack_from("<Q", memory, position + 1184)[0],
                    "free_page_count": struct.unpack_from("<Q", memory, position + 1192)[0],
                    "mapping_self_test": struct.unpack_from("<I", memory, position + 1200)[0],
                    "dynamic_mapping_base": struct.unpack_from("<Q", memory, position + 1216)[0],
                    "storage_irqs": struct.unpack_from("<Q", memory, position + 1224)[0],
                    "storage_interrupt_kind": struct.unpack_from("<I", memory, position + 1232)[0],
                    "storage_cause": struct.unpack_from("<I", memory, position + 1236)[0],
                    "storage_state": struct.unpack_from("<I", memory, position + 1240)[0],
                    "framebuffer_width": struct.unpack_from("<I", memory, position + 128)[0],
                    "framebuffer_height": struct.unpack_from("<I", memory, position + 132)[0],
                    "framebuffer_stride": struct.unpack_from("<I", memory, position + 136)[0],
                    "framebuffer_format": struct.unpack_from("<I", memory, position + 140)[0],
                    "cursor_y": struct.unpack_from("<I", memory, position + 148)[0],
                    "ring_head": struct.unpack_from("<I", memory, position + 1168)[0],
                    "ring_tail": struct.unpack_from("<I", memory, position + 1172)[0],
                    "ring_dropped": struct.unpack_from("<I", memory, position + 1176)[0],
                    "event_dropped": struct.unpack_from("<I", memory, position + 1256)[0],
                    "device_irqs": struct.unpack_from("<Q", memory, position + 2304)[0],
                    "device_vector": struct.unpack_from("<I", memory, position + 2312)[0],
                    "ticks_per_millisecond": struct.unpack_from("<Q", memory, position + 2344)[0],
                    "clock_state": struct.unpack_from("<I", memory, position + 2352)[0],
                    "stage2_state": struct.unpack_from("<I", memory, position + 2360)[0],
                    "xhci_mapping": struct.unpack_from("<Q", memory, position + 2368)[0],
                    "xhci_mapping_size": struct.unpack_from("<Q", memory, position + 2376)[0],
                    "xhci_state": struct.unpack_from("<I", memory, position + 2384)[0],
                    "xhci_cause": struct.unpack_from("<I", memory, position + 2388)[0],
                    "xhci_port": struct.unpack_from("<I", memory, position + 2392)[0],
                    "xhci_slot": struct.unpack_from("<I", memory, position + 2396)[0],
                    "xhci_commands": struct.unpack_from("<Q", memory, position + 2400)[0],
                    "xhci_transfers": struct.unpack_from("<Q", memory, position + 2408)[0],
                    "xhci_port_changes": struct.unpack_from("<Q", memory, position + 2416)[0],
                    "xhci_reports": struct.unpack_from("<Q", memory, position + 2424)[0],
                    "xhci_recoveries": struct.unpack_from("<I", memory, position + 2432)[0],
                    "xhci_dma": struct.unpack_from("<Q", memory, position + 2440)[0],
                    "xhci_message_mode": struct.unpack_from("<I", memory, position + 2448)[0],
                    "xhci_configuration": struct.unpack_from("<I", memory, position + 2452)[0],
                    "xhci_hotplug": struct.unpack_from("<Q", memory, position + 2464)[0],
                    "usb_kind": struct.unpack_from("<I", memory, position + 2472)[0],
                    "usb_configuration": struct.unpack_from("<I", memory, position + 2476)[0],
                    "usb_sector_size": struct.unpack_from("<I", memory, position + 2480)[0],
                    "usb_sector_count": struct.unpack_from("<Q", memory, position + 2488)[0],
                    "usb_reads": struct.unpack_from("<Q", memory, position + 2496)[0],
                    "usb_sense_key": struct.unpack_from("<I", memory, position + 2504)[0],
                    "usb_gpt_status": struct.unpack_from("<I", memory, position + 2512)[0],
                    "usb_mount_status": struct.unpack_from("<I", memory, position + 2516)[0],
                    "usb_bot_stage": struct.unpack_from("<I", memory, position + 2524)[0],
                    "user_state": struct.unpack_from("<I", memory, position + 2576)[0],
                    "user_exit": struct.unpack_from("<I", memory, position + 2580)[0],
                    "user_fault": struct.unpack_from("<I", memory, position + 2584)[0],
                    "user_runs": struct.unpack_from("<I", memory, position + 2588)[0],
                    "user_instructions": struct.unpack_from("<Q", memory, position + 2592)[0],
                    "user_descriptors": struct.unpack_from("<I", memory, position + 3460)[0],
                    "user_pid": struct.unpack_from("<I", memory, position + 3464)[0],
                    "panic_vector": struct.unpack_from("<I", memory, position + 2600)[0],
                    "panic_error_valid": struct.unpack_from("<I", memory, position + 2604)[0],
                    "panic_error": struct.unpack_from("<Q", memory, position + 2608)[0],
                    "panic_rip": struct.unpack_from("<Q", memory, position + 2616)[0],
                    "panic_cs": struct.unpack_from("<Q", memory, position + 2624)[0],
                    "panic_rflags": struct.unpack_from("<Q", memory, position + 2632)[0],
                    "panic_rsp": struct.unpack_from("<Q", memory, position + 2640)[0],
                    "panic_cr2": struct.unpack_from("<Q", memory, position + 2648)[0],
					"panic_state": struct.unpack_from("<I", memory, position + 2672)[0],
					"panic_qr_entry": struct.unpack_from("<Q", memory, position + 3616)[0],
					"panic_qr_scratch": struct.unpack_from("<Q", memory, position + 3664)[0],
					"panic_stack_base": struct.unpack_from("<Q", memory, position + 3672)[0],
                    "panic_stack_top": struct.unpack_from("<Q", memory, position + 3680)[0],
                    "dma_reservation_pages": struct.unpack_from("<I", memory, position + 296)[0],
                }
            position += 4


def capture_record(monitor_path, memory_path):
    monitor_command(monitor_path, f'pmemsave 0 0x10000000 "{memory_path}"')
    record = kernel_record(memory_path)
    if record is None:
        raise RuntimeError("QEMU memory did not contain KernelBootInfo")
    return record


def capture_screen(monitor_path, path, device=None):
    target = f' {device}' if device else ''
    monitor_command(monitor_path, f'screendump "{path}"{target}')
    data = Path(path).read_bytes()
    header = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", data)
    if header is None or int(header.group(3)) != 255:
        raise AssertionError("QEMU did not produce a 24-bit PPM screenshot")
    width, height = int(header.group(1)), int(header.group(2))
    pixels = data[header.end():]
    if len(pixels) != width * height * 3:
        raise AssertionError("QEMU screenshot pixel count is invalid")
    return width, height, pixels


def screen_lines(screen):
    """Decode the kernel's fixed 8x8 glyph cells from a QEMU screenshot."""
    source = Path(__file__).resolve().parents[2] / "src/kernel/console/FramebufferTerminal.hy"
    rows = [0] * 760
    assignments = re.findall(r"font\[(\d+)\] = (-?\d+);", source.read_text())
    if len(assignments) != 190:
        raise AssertionError("framebuffer font table is incomplete")
    for index, value in assignments:
        rows[int(index) * 4:int(index) * 4 + 4] = list(struct.pack("<i", int(value)))
    glyphs = {tuple(rows[i * 8:i * 8 + 8]): chr(i + 32) for i in range(95)}
    width, height, pixels = screen
    lines = []
    for y in range(0, height - 7, 8):
        characters = []
        for x in range(0, width - 7, 8):
            glyph = []
            for row in range(8):
                bits = 0
                for column in range(8):
                    offset = ((y + row) * width + x + column) * 3
                    if pixels[offset] > 127:
                        bits |= 128 >> column
                glyph.append(bits)
            characters.append(glyphs.get(tuple(glyph), "?"))
        lines.append("".join(characters))
    return lines


def read_until(connection, marker, timeout, process):
    deadline = time.monotonic() + timeout
    received = bytearray()
    left_userland = False
    while marker not in received:
        if process.poll() is not None:
            raise RuntimeError(f"QEMU exited with status {process.returncode}")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("serial output timed out:\n" + received[-6000:].decode(errors="replace"))
        connection.settimeout(min(remaining, 1))
        try:
            part = connection.recv(4096)
        except socket.timeout:
            continue
        if not part:
            raise RuntimeError(f"serial connection closed: {bytes(received[-300:])!r}")
        received.extend(part)
        # Legacy KMon integration checks deliberately leave the first normal
        # userland session before exercising recovery-console commands.
        if marker == PROMPT and not left_userland and b"australis> " in received:
            connection.sendall(b"exit\r")
            left_userland = True
    return bytes(received)


def drain_until_quiet(connection, process, quiet_seconds=0.25, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"QEMU exited with status {process.returncode}")
        connection.settimeout(quiet_seconds)
        try:
            if not connection.recv(4096):
                raise RuntimeError("serial connection closed during overflow recovery")
        except socket.timeout:
            return
    raise TimeoutError("serial input did not become quiet after overflow")


def command(connection, process, input_bytes, expected_output):
    connection.sendall(input_bytes + b"\r")
    response = read_until(connection, b"\n" + PROMPT, 20, process)
    if expected_output not in response:
        raise AssertionError(
            f"command {input_bytes!r} expected {expected_output!r}; got {response!r}"
        )
    return response


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    hyfs2 = len(sys.argv) > 5 and sys.argv[5] == "hyfs2"
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    rootfs = Path(__file__).resolve().parents[2] / "rootfs"
    hello = (rootfs / "hello.txt").read_bytes()
    readme = (rootfs / "readme.txt").read_bytes()
    fault = (rootfs / "fault.txt").read_bytes()
    with tempfile.TemporaryDirectory(prefix="australis-serial-") as temporary:
        serial_path = os.path.join(temporary, "serial.sock")
        monitor_path = os.path.join(temporary, "monitor.sock")
        memory_path = os.path.join(temporary, "ram.bin")
        arguments = [
            qemu, "-machine", "q35", "-m", "256M",
            "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
            "-cdrom", iso, "-display", "none",
            "-monitor", f"unix:{monitor_path},server=on,wait=off",
            "-net", "none", "-no-reboot",
            "-serial", f"unix:{serial_path},server=on,wait=off",
        ]
        if transport == "ahci":
            arguments += [
                "-device", "ich9-ahci,id=ahci0",
                "-drive", f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
                "-device", "ide-hd,drive=sata0,bus=ahci0.0",
            ]
        else:
            arguments += [
                "-drive", f"if=none,id=nvme0,format=raw,readonly=on,file={iso}",
                "-device", "nvme,serial=australis,drive=nvme0",
            ]
        process = subprocess.Popen(arguments, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 10
            while not os.path.exists(serial_path):
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open its serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(serial_path)
                opening = read_until(connection, PROMPT, 60, process)
                if BANNER not in opening:
                    raise AssertionError(f"kernel console banner missing: {opening[-500:]!r}")
                before = capture_record(monitor_path, memory_path)
                # IRQ4 may deliver and echo bytes, but a command is submitted
                # only when the normal-context shell consumes Enter.
                connection.sendall(b"version")
                read_until(connection, b"version", 10, process)
                before_enter = capture_record(monitor_path, memory_path)
                if before_enter["command_count"] != before["command_count"]:
                    raise AssertionError("serial IRQ delivery executed a command before Enter")
                connection.sendall(b"\r")
                submitted = read_until(connection, b"\n" + PROMPT, 20, process)
                if VERSION not in submitted:
                    raise AssertionError(f"deferred version command failed: {submitted!r}")
                after_enter = capture_record(monitor_path, memory_path)
                if after_enter["command_count"] != before["command_count"] + 1:
                    raise AssertionError("normal-context shell did not submit exactly one command")
                drive_id = "sata0" if transport == "ahci" else "nvme0"
                monitor_command(monitor_path, f"block_set_io_throttle {drive_id} 0 0 0 0 1 0")
                command(connection, process, b"cat /fault.txt", fault)
                command(connection, process, b"cat /fault.txt", fault)
                delayed_start = time.monotonic()
                command(connection, process, b"cat /fault.txt", fault)
                delayed_elapsed = time.monotonic() - delayed_start
                monitor_command(monitor_path, f"block_set_io_throttle {drive_id} 0 0 0 0 0 0")
                delayed = capture_record(monitor_path, memory_path)
                if delayed_elapsed < 0.2 or delayed["storage_irqs"] <= before["storage_irqs"]:
                    raise AssertionError(f"QEMU read did not wait for delayed completion: {delayed_elapsed:.3f}s")
                command(connection, process, b"help",
                        b"Commands: help, echo, ls [path], stat <path>, cat <path>, devices, mounts, pwd, path [dirs], run <program>, ps, version, status, bootinfo, memmap, pages, continue, reboot, halt, trace, registers, panic [gp] (D boot)\r\n")
                command(connection, process, b"status", b"KMon system status:\r\n")
                command(connection, process, b"bootinfo", b"KernelBootInfo:\r\nABI version: 7\r\n")
                command(connection, process, b"continue", b"Normal boot is already active.\r\n")
                trace = command(connection, process, b"trace", b"KMon diagnostic trace:\r\n")
                if b"recent commands (oldest first):\r\n" not in trace or b"  continue\r\n" not in trace:
                    raise AssertionError(f"KMon trace missing recent commands: {trace!r}")
                registers = command(connection, process, b"registers", b"Live CPU registers (decimal):\r\n")
                for name in (b"RIP: ", b"RSP: ", b"RBP: ", b"RFLAGS: ", b"CR3: "):
                    if re.search(re.escape(name) + rb"[1-9][0-9]*\r\n", registers) is None:
                        raise AssertionError(f"KMon register snapshot missing {name!r}: {registers!r}")
                command(connection, process, b"panic", b"panic requires D debug boot.\r\n")
                for name in (b"continue", b"reboot", b"halt", b"trace", b"status", b"bootinfo", b"registers"):
                    command(connection, process, name + b" extra", b"Usage: " + name + b"\r\n")
                command(connection, process, b"panic extra", b"Usage: panic [gp]\r\n")
                command(connection, process, b"echo hello serial", b"hello serial\r\n")
                command(connection, process, b"echo ab\x08c", b"\r\nac\r\n")
                command(connection, process, b"echo discard\x15echo kept", b"\r\nkept\r\n")
                command(connection, process, b"echo ab\x1b[DZ", b"\r\naZb\r\n")
                command(connection, process, b"echo abc\x1b[D\x1b[3~", b"\r\nab\r\n")
                command(connection, process, b"Xecho home\x1b[H\x1b[3~", b"\r\nhome\r\n")
                command(connection, process, b"echo en\x1b[H\x1b[Fd", b"\r\nend\r\n")
                command(connection, process, b"\x1b[A", b"\r\nend\r\n")
                command(connection, process, b"\x0cecho clear", b"\r\nclear\r\n")
                command(connection, process, b"x" * 257, b"Input line is too long.\r\n")
                listing = command(connection, process, b"ls", b"fault.txt\r\n")
                for entry in (b"hello.txt\r\n", b"readme.txt\r\n",
                              b"user-demo.exec\r\n", b"user-fault.exec\r\n"):
                    if entry not in listing:
                        raise AssertionError(f"root listing missing {entry!r}: {listing!r}")
                if hyfs2:
                    system_listing = command(connection, process, b"ls /System",
                                             b"Core\r\n")
                    if b"hexviewer.exec\r\n" not in system_listing:
                        raise AssertionError(f"Hex Viewer missing from /System: {system_listing!r}")
                    command(connection, process, b"stat /System/hexviewer.exec",
                            b"type: file\r\n")
                    command(connection, process, b"path", b"PATH=/System/Bin:/System:/\r\n")
                    command(connection, process, b"hexviewer", b"Hello, World!\r\n")
                    command(connection, process, b"path /System/Bin:/System", b"PATH=/System/Bin:/System\r\n")
                    command(connection, process, b"run hexviewer", b"Hello, World!\r\n")
                    command(connection, process, b"PATH=/System", b"PATH=/System\r\n")
                    command(connection, process, b"hexviewer", b"Hello, World!\r\n")
                    command(connection, process, b"run /System/hexviewer.exec",
                            b"Hello, World!\r\n")
                    command(connection, process, b"run /System/hexviewer",
                            b"Hello, World!\r\n")
                    command(connection, process, b"path /missing", b"PATH directory not found.\r\n")
                    command(connection, process, b"path", b"PATH=/System\r\n")
                    command(connection, process, b"path /System/Bin:/System:/", b"PATH=/System/Bin:/System:/\r\n")
                    command(connection, process, b"ls /System/Bin", b"user-demo.exec\r\n")
                    connection.sendall(b"cat /System/Bin/user-demo.exec\r")
                    binary = read_until(connection, PROMPT, 30, process)
                    if b"AUEX" not in binary:
                        raise AssertionError(f"cat lost executable bytes: {binary[-200:]!r}")
                    metadata = command(connection, process, b"stat /System", b"type: directory\r\n")
                    if b"created: unavailable\r\n" not in metadata or b"id: 0\r\n" in metadata:
                        raise AssertionError(f"HyFS v2 metadata missing: {metadata!r}")
                    command(connection, process, b"stat /System/Bin/user-demo.exec/",
                            b"File not found.\r\n")
                else:
                    command(connection, process, b"stat /hello.txt", b"id: unavailable\r\n")
                    command(connection, process, b"hello-world", b"Hello, World!\r\n")
                command(connection, process, b"cat /hello.txt", hello)
                command(connection, process, b"cat /readme.txt", readme)
                command(connection, process, b"cat /missing.txt", b"cat: open failed (status):\r\n4\r\n")
                command(connection, process, b"cat", b"Usage: cat <path>\r\n")
                command(connection, process, b"unknown", b"Unknown command. Type help.\r\n")
                command(connection, process, b"version", VERSION)
                repeat = 0
                while repeat < 16:
                    command(connection, process, b"cat /hello.txt", hello)
                    repeat += 1
                # Deliver a burst of serial input while the kernel repeatedly
                # waits for storage completions and reads the larger root file.
                connection.sendall(b"cat /readme.txt\r" * 24)
                burst = bytearray()
                while burst.count(PROMPT) < 24:
                    burst.extend(read_until(connection, PROMPT, 30, process))
                if burst.count(readme) != 24 or burst.count(PROMPT) != 24:
                    raise AssertionError("concurrent serial/storage burst lost or corrupted a read")
                command(connection, process, b"echo a\x08b", b"\r\nb\r\n")
                command(connection, process, b"echo discard\x15echo kept", b"\r\nkept\r\n")
                after = capture_record(monitor_path, memory_path)
                if (after["serial_flags"] != 3 or after["serial_irqs"] <= before["serial_irqs"] or
                        after["ring_head"] != after["ring_tail"] or after["ring_dropped"] != 0 or
                        after["event_dropped"] != 0 or
                        after["memory_error"] != 0 or after["mapping_error"] != 0 or after["transient_floor"] == 0 or
                        (after["free_page_count"] == 0) != (after["free_page_head"] == 0) or
                        after["mapping_self_test"] != 0 or
                        after["dynamic_mapping_base"] != before["dynamic_mapping_base"] or
                        after["storage_irqs"] <= before["storage_irqs"] or
                        after["storage_interrupt_kind"] != (1 if transport == "ahci" else 2) or
                        after["storage_cause"] != 0 or after["storage_state"] != 0 or
                        after["allocator_next"] != after["transient_floor"] or
                        after["allocator_next"] != before["allocator_next"]):
                    raise AssertionError(f"unexpected hardened kernel state: before={before}, after={after}")

                command(connection, process, b"cat /hello.txt", hello)
                root_screen = capture_screen(monitor_path, os.path.join(temporary, "root.ppm"))
                visible_lines = screen_lines(root_screen)
                if not any("Hello from Australis HyFS." in row for row in visible_lines):
                    raise AssertionError(f"root file text is missing from the framebuffer: {visible_lines[-8:]!r}")
                if not visible_lines[-1].startswith("kmon> _"):
                    raise AssertionError(f"framebuffer prompt or cursor is missing: {visible_lines[-1][:25]!r}")

                # A blank command advances exactly one text row. Once the
                # cursor reaches the bottom, every older pixel row must move
                # upward by one 8-pixel glyph height, not wrap to row zero.
                remaining_rows = max(0, (after["framebuffer_height"] - after["cursor_y"] - 8) // 8)
                for _ in range(remaining_rows):
                    command(connection, process, b"", b"\r\n")
                screen_before = capture_screen(monitor_path, os.path.join(temporary, "before.ppm"))
                command(connection, process, b"", b"\r\n")
                screen_after = capture_screen(monitor_path, os.path.join(temporary, "after.ppm"))
                width, height, old_pixels = screen_before
                comparable_rows = (height // 8) * 8 - 16
                if (width, height) != (after["framebuffer_width"], after["framebuffer_height"]) or \
                        screen_after[:2] != screen_before[:2] or \
                        screen_after[2][: comparable_rows * width * 3] != \
                        old_pixels[8 * width * 3:(8 + comparable_rows) * width * 3]:
                    raise AssertionError("framebuffer terminal did not scroll one complete glyph row")

                # The IRQ handler must count bytes dropped while a storage
                # request stalls the shell; it must never execute the command.
                monitor_command(monitor_path, f"block_set_io_throttle {drive_id} 0 0 0 0 1 0")
                connection.sendall(b"cat /fault.txt\r")
                read_until(connection, b"cat /fault.txt", 10, process)
                connection.sendall(b"x" * 4096)
                read_until(connection, PROMPT, 30, process)
                monitor_command(monitor_path, f"block_set_io_throttle {drive_id} 0 0 0 0 0 0")
                # The pending event queue may still be echoing the accepted
                # bytes. Let it drain before testing that Ctrl-C recovers input.
                drain_until_quiet(connection, process)
                connection.sendall(b"\x03")
                read_until(connection, PROMPT, 30, process)
                overflowed = capture_record(monitor_path, memory_path)
                if overflowed["ring_dropped"] <= after["ring_dropped"]:
                    raise AssertionError("serial receive-ring overflow was not counted")
                command(connection, process, b"version", VERSION)
            print(f"Australis {transport.upper()} interactive serial console passed")
        except BaseException as error:
            if os.path.exists(monitor_path):
                monitor_command(monitor_path, f'pmemsave 0 0x10000000 "{memory_path}"')
                raise RuntimeError(f"{error}; kernel record: {kernel_record(memory_path)}") from error
            raise
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    main()
