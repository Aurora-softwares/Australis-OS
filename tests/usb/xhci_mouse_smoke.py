#!/usr/bin/env python3
"""Boot a USB mouse and prove xHCI reports leave the IRQ path safely."""

import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import PROMPT, capture_record, command, monitor_command, read_until


def main():
    if len(sys.argv) != 5 or sys.argv[4] not in ("ahci", "nvme"):
        raise SystemExit("usage: xhci_mouse_smoke.py QEMU OVMF ISO ahci|nvme")
    qemu, ovmf, iso, transport = sys.argv[1:]
    with tempfile.TemporaryDirectory(prefix="australis-mouse-") as temporary:
        serial = os.path.join(temporary, "serial.sock")
        monitor = os.path.join(temporary, "monitor.sock")
        memory = os.path.join(temporary, "memory.bin")
        arguments = [qemu, "-machine", "q35", "-m", "256M", "-drive",
            f"if=pflash,format=raw,readonly=on,file={ovmf}", "-cdrom", iso,
            "-device", "qemu-xhci,id=xhci0", "-device", "usb-mouse,id=mouse0,bus=xhci0.0",
            "-net", "none", "-display", "none", "-no-reboot",
            "-serial", f"unix:{serial},server=on,wait=off",
            "-monitor", f"unix:{monitor},server=on,wait=off"]
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
            while not os.path.exists(serial):
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(serial)
                read_until(connection, PROMPT, 75, process)
                before = capture_record(monitor, memory)
                if (before["xhci_state"] != 14 or before["usb_kind"] != 3 or
                    before["xhci_port"] == 0 or before["xhci_slot"] == 0 or
                    before["xhci_dma"] == 0):
                    raise AssertionError(f"boot mouse did not initialize: {before}")
                command(connection, process, b"devices", b"usb0: mouse ready\r\n")
                initial_commands = capture_record(monitor, memory)["command_count"]
                monitor_command(monitor, "mouse_move 6 -4")
                monitor_command(monitor, "mouse_button 1")
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    after = capture_record(monitor, memory)
                    if after["xhci_reports"] > before["xhci_reports"]:
                        break
                    time.sleep(0.1)
                else:
                    raise AssertionError("mouse motion did not produce an xHCI report")
                if after["command_count"] != initial_commands:
                    raise AssertionError("mouse IRQ executed a shell command")
                command(connection, process, b"echo mouse alive", b"mouse alive\r\n")
                monitor_command(monitor, "device_del mouse0")
                time.sleep(0.4)
                command(connection, process, b"devices", b"usb0: removed or unavailable\r\n")
                monitor_command(monitor, "device_add usb-mouse,id=mouse1,bus=xhci0.0")
                time.sleep(0.7)
                command(connection, process, b"devices", b"usb0: mouse ready\r\n")
                monitor_command(monitor, "mouse_move -3 2")
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    recovered = capture_record(monitor, memory)
                    if recovered["xhci_reports"] > after["xhci_reports"]:
                        break
                    time.sleep(0.1)
                else:
                    raise AssertionError("reconnected mouse did not deliver a report")
                if recovered["xhci_recoveries"] == 0 or recovered["xhci_dma"] != before["xhci_dma"]:
                    raise AssertionError(f"mouse recovery lost DMA ownership: {recovered}")
                command(connection, process, b"echo mouse recovered", b"mouse recovered\r\n")
                print(f"Australis xHCI mouse {transport} boot and report test passed")
        finally:
            process.terminate()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()


if __name__ == "__main__":
    main()
