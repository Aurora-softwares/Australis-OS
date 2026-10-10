#!/usr/bin/env python3
"""Trigger a real kernel page fault and verify both panic terminals."""

from pathlib import Path
import os
import re
import socket
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import (PROMPT, capture_record, capture_screen, read_until,
                               screen_lines)


def main():
    qemu, firmware, iso = sys.argv[1:4]
    with tempfile.TemporaryDirectory(prefix="australis-panic-") as temporary:
        serial_path = os.path.join(temporary, "serial.sock")
        monitor_path = os.path.join(temporary, "monitor.sock")
        memory_path = os.path.join(temporary, "ram.bin")
        screen_path = os.path.join(temporary, "panic.ppm")
        arguments = [
            qemu, "-machine", "q35", "-m", "256M",
            "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
            "-cdrom", iso, "-display", "none", "-no-reboot", "-net", "none",
            "-monitor", f"unix:{monitor_path},server=on,wait=off",
            "-serial", f"unix:{serial_path},server=on,wait=off",
            "-device", "ich9-ahci,id=ahci0",
            "-drive", f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
            "-device", "ide-hd,drive=sata0,bus=ahci0.0",
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
                read_until(connection, PROMPT, 60, process)
                connection.sendall(b"panic-test\r")
                report = read_until(connection,
                    b"System halted. Power cycle or reset to continue.\r\n", 20, process)

            required = [
                b"*** AUSTRALIS KERNEL PANIC ***\r\n",
                b"Fatal CPU exception; interrupts are disabled.\r\n",
                b"VECTOR  =0x000000000000000E\r\n",
                b"ERROR   =0x0000000000000000\r\n",
                b"CR2     =0x0000000000000000\r\n",
                b"R15     =0x",
            ]
            for marker in required:
                if marker not in report:
                    raise AssertionError(f"serial panic report missing {marker!r}: {report[-1200:]!r}")
            for register in (b"RIP", b"RFLAGS", b"RSP", b"RAX"):
                if re.search(register + rb" + =?0x[0-9A-F]{16}", report) is None:
                    raise AssertionError(f"serial panic register missing: {register!r}")

            record = capture_record(monitor_path, memory_path)
            if (record["exception"] != 14 or record["panic_vector"] != 14 or
                    record["panic_error_valid"] != 1 or record["panic_error"] != 0 or
                    record["panic_cr2"] != 0 or record["panic_rip"] == 0 or
                    record["panic_rsp"] == 0 or record["panic_state"] != 2):
                raise AssertionError(f"invalid captured panic state: {record}")

            lines = [line.rstrip() for line in screen_lines(
                capture_screen(monitor_path, screen_path))]
            visible = "\n".join(lines)
            for marker in ("*** AUSTRALIS KERNEL PANIC ***",
                           "VECTOR  =0x000000000000000E",
                           "RIP     =0x", "System halted. Power cycle or reset to continue."):
                if marker not in visible:
                    raise AssertionError(f"framebuffer panic report missing {marker!r}")
            print("Australis kernel panic QEMU test passed")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
            if process.stderr is not None:
                process.stderr.close()


if __name__ == "__main__":
    main()
