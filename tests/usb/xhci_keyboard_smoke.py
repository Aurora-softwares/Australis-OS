#!/usr/bin/env python3
"""Exercise xHCI boot-keyboard input, buffering, and recovery in QEMU."""

import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import (PROMPT, capture_record, capture_screen, command,
                               monitor_command, read_until, screen_lines)


KEYS = {" ": "spc", "/": "slash", ".": "dot", "\n": "ret", "-": "minus"}


def send_text(monitor, text, delay=0.04):
    for character in text:
        key = KEYS.get(character, character.lower())
        if character.isupper():
            key = "shift-" + key
        monitor_command(monitor, f"sendkey {key} 20")
        time.sleep(delay)


def read_prompts(connection, process, count, timeout=30):
    deadline = time.monotonic() + timeout
    received = bytearray()
    while received.count(PROMPT) < count:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"waiting for {count} prompts: {bytes(received[-500:])!r}")
        received.extend(read_until(connection, PROMPT, remaining, process))
    return bytes(received)


def main():
    if len(sys.argv) != 5:
        raise SystemExit("usage: xhci_keyboard_smoke.py QEMU OVMF ISO ahci|nvme")
    qemu, ovmf, iso, transport = sys.argv[1:]
    if transport not in ("ahci", "nvme"):
        raise SystemExit("transport must be ahci or nvme")
    root = Path(__file__).resolve().parents[2]
    hello = (root / "rootfs" / "hello.txt").read_bytes()
    fault = (root / "rootfs" / "fault.txt").read_bytes()
    with tempfile.TemporaryDirectory(prefix="australis-xhci-") as temporary:
        serial_path = os.path.join(temporary, "serial.sock")
        monitor_path = os.path.join(temporary, "monitor.sock")
        memory_path = os.path.join(temporary, "memory.bin")
        screen_path = os.path.join(temporary, "screen.ppm")
        arguments = [qemu, "-machine", "q35", "-m", "256M", "-drive",
            f"if=pflash,format=raw,readonly=on,file={ovmf}", "-cdrom", iso,
            "-device", "qemu-xhci,id=xhci0", "-device",
            "usb-kbd,id=kbd0,bus=xhci0.0", "-net", "none", "-display", "none",
            "-no-reboot", "-serial", f"unix:{serial_path},server=on,wait=off",
            "-monitor", f"unix:{monitor_path},server=on,wait=off"]
        drive_id = "sata0" if transport == "ahci" else "nvme0"
        if transport == "ahci":
            arguments += ["-device", "ich9-ahci,id=ahci0", "-drive",
                f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
                "-device", "ide-hd,drive=sata0,bus=ahci0.0"]
        else:
            arguments += ["-drive", f"if=none,id=nvme0,format=raw,readonly=on,file={iso}",
                "-device", "nvme,serial=australis,drive=nvme0"]
        process = subprocess.Popen(arguments, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 10
            while not os.path.exists(serial_path):
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(serial_path)
                read_until(connection, PROMPT, 75, process)
                before = capture_record(monitor_path, memory_path)
                if (before["xhci_state"] != 10 or before["xhci_cause"] != 0 or
                    before["device_vector"] != 50 or before["xhci_port"] == 0 or
                    before["xhci_slot"] == 0 or before["xhci_dma"] == 0 or
                    before["xhci_message_mode"] not in (1, 2) or
                    before["xhci_configuration"] == 0 or before["device_irqs"] == 0):
                    raise AssertionError(f"xHCI keyboard did not initialize: {before}")

                # Key reports may echo characters, but Enter and command
                # execution remain in the shell's normal context.
                initial_commands = before["command_count"]
                send_text(monitor_path, "version")
                read_until(connection, b"version", 10, process)
                before_enter = capture_record(monitor_path, memory_path)
                if before_enter["command_count"] != initial_commands:
                    raise AssertionError("USB IRQ delivery executed a command before Enter")
                send_text(monitor_path, "\n")
                version = read_until(connection, b"\n" + PROMPT, 15, process)
                if b"version: 0.0.1\r\n" not in version:
                    raise AssertionError(f"USB version command failed: {version!r}")

                send_text(monitor_path, "cat /hello.txt\n")
                usb_read = read_until(connection, b"\n" + PROMPT, 20, process)
                if hello not in usb_read:
                    raise AssertionError(f"USB root read failed: {usb_read!r}")

                # The same decoded HID event path becomes AUEX fd 0 while a
                # program is scheduled. Its writes remain mirrored to COM1
                # and the framebuffer through fd 1.
                send_text(monitor_path, "run /user-demo.exec\n")
                read_until(connection, b"user> ", 20, process)
                send_text(monitor_path, "usb input\n")
                user_output = read_until(connection, b"\n" + PROMPT, 30, process)
                if (b"input: usb input\r\n" not in user_output or hello not in user_output or
                        b"User program exited cleanly.\r\n" not in user_output):
                    raise AssertionError(f"USB user-terminal syscall failed: {user_output!r}")
                command(connection, process, b"echo com1 alive", b"com1 alive\r\n")

                # Hold a key longer than the initial repeat delay, then clear
                # the line with Ctrl-U. This proves make, repeat, and break
                # reports all pass through the common line editor.
                monitor_command(monitor_path, "sendkey a 800")
                time.sleep(1.0)
                monitor_command(monitor_path, "sendkey ctrl-u 20")
                time.sleep(0.1)
                send_text(monitor_path, "echo repeat ok\n")
                repeated = read_until(connection, b"\n" + PROMPT, 20, process)
                if repeated.count(b"a") < 3 or b"repeat ok\r\n" not in repeated:
                    raise AssertionError(f"USB key repeat or key-up failed: {repeated!r}")

                # Cross the 255-TRB link boundary (press and release are two
                # reports per key) and then prove the editor still receives a
                # complete command from the recycled report buffers.
                send_text(monitor_path, "a" * 140, 0.01)
                monitor_command(monitor_path, "sendkey ctrl-u 20")
                time.sleep(0.1)
                send_text(monitor_path, "echo ring wrap ok\n")
                wrapped = read_until(connection, b"\n" + PROMPT, 25, process)
                if b"ring wrap ok\r\n" not in wrapped:
                    raise AssertionError(f"USB transfer-ring wrap failed: {wrapped[-500:]!r}")

                # Queue a complete keyboard command while a deliberately slow
                # root read owns normal context. The 32-report transfer window
                # must preserve it until the read returns.
                monitor_command(monitor_path, f"block_set_io_throttle {drive_id} 0 0 0 0 1 0")
                connection.sendall(b"cat /fault.txt\r")
                time.sleep(0.1)
                send_text(monitor_path, "version\n", 0.03)
                queued = read_prompts(connection, process, 2, 30)
                monitor_command(monitor_path, f"block_set_io_throttle {drive_id} 0 0 0 0 0 0")
                if fault not in queued or b"version: 0.0.1\r\n" not in queued:
                    raise AssertionError(f"buffered USB input was lost during a root read: {queued!r}")

                # Rebuild the controller after removal. COM1 is the recovery
                # path and must stay usable throughout every cycle.
                recovery_pages = None
                for cycle in range(3):
                    monitor_command(monitor_path, f"device_del kbd{cycle}")
                    time.sleep(0.35)
                    command(connection, process, f"echo unplug {cycle}".encode(),
                            f"unplug {cycle}\r\n".encode())
                    monitor_command(monitor_path,
                        f"device_add usb-kbd,id=kbd{cycle + 1},bus=xhci0.0")
                    time.sleep(0.6)
                    command(connection, process, f"echo recover {cycle}".encode(),
                            f"recover {cycle}\r\n".encode())
                    send_text(monitor_path, f"echo usb{cycle}\n")
                    restored = read_until(connection, b"\n" + PROMPT, 20, process)
                    if f"usb{cycle}\r\n".encode() not in restored:
                        raise AssertionError(f"USB input did not recover in cycle {cycle}: {restored!r}")
                    cycle_record = capture_record(monitor_path, memory_path)
                    cycle_pages = (cycle_record["allocator_next"], cycle_record["free_page_count"],
                                   cycle_record["xhci_dma"])
                    if recovery_pages is None:
                        recovery_pages = cycle_pages
                    elif cycle_pages != recovery_pages:
                        raise AssertionError(
                            f"xHCI recovery did not reuse its pages: first={recovery_pages}, now={cycle_pages}"
                        )

                screen = capture_screen(monitor_path, screen_path)
                if not any("usb2" in line for line in screen_lines(screen)):
                    raise AssertionError("USB command output was not mirrored to the framebuffer")
                after = capture_record(monitor_path, memory_path)
                if (after["xhci_state"] != 10 or after["xhci_cause"] != 0 or
                    after["xhci_recoveries"] < 3 or after["xhci_hotplug"] < 3 or
                    after["device_irqs"] <= before["device_irqs"] or
                    after["xhci_transfers"] <= before["xhci_transfers"] or
                    after["xhci_reports"] <= before["xhci_reports"] or
                    after["xhci_dma"] != before["xhci_dma"] or
                    after["allocator_next"] // 4096 - after["free_page_count"] !=
                    before["allocator_next"] // 4096 - before["free_page_count"] or
                    after["dynamic_mapping_base"] != before["dynamic_mapping_base"] or
                    after["ring_dropped"] != 0 or after["event_dropped"] != 0 or
                    after["device_vector"] != 50):
                    raise AssertionError(f"xHCI recovery leaked or lost state: before={before}, after={after}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait(timeout=5)
    print(f"Australis {transport.upper()} xHCI keyboard QEMU test passed")


if __name__ == "__main__":
    main()
