#!/usr/bin/env python3
"""Verify simultaneous keyboard and mouse reports from distinct xHCI slots."""

from pathlib import Path
import os
import socket
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import PROMPT, capture_record, monitor_command, read_until
from xhci_multi_smoke import send_version, wait_devices


def mouse_report(monitor, memory, before):
    monitor_command(monitor, "mouse_move 6 -4")
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        after = capture_record(monitor, memory)
        if after["xhci_reports"] > before:
            return after["xhci_reports"]
        time.sleep(0.1)
    raise AssertionError("mouse report did not arrive while keyboard was active")


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    iso = str(Path(iso).resolve())
    with tempfile.TemporaryDirectory(prefix="australis-xhci-dual-hid-") as directory:
        serial = os.path.join(directory, "serial.sock")
        monitor = os.path.join(directory, "monitor.sock")
        memory = os.path.join(directory, "memory.bin")
        command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
                   f"if=pflash,format=raw,readonly=on,file={firmware}",
                   "-cdrom", iso, "-device", "qemu-xhci,id=xhci0",
                   "-device", "usb-kbd,id=kbd0,bus=xhci0.0",
                   "-device", "usb-mouse,id=mouse0,bus=xhci0.0",
                   "-net", "none", "-display", "none", "-no-reboot",
                   "-serial", f"unix:{serial},server=on,wait=off",
                   "-monitor", f"unix:{monitor},server=on,wait=off"]
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
                wait_devices(connection, process,
                             [b"keyboard ready", b"mouse ready"])
                send_version(monitor, connection, process)
                before = capture_record(monitor, memory)
                reports = mouse_report(monitor, memory, before["xhci_reports"])
                monitor_command(monitor, "device_del mouse0")
                time.sleep(0.45)
                wait_devices(connection, process, [b"keyboard ready"])
                send_version(monitor, connection, process)
                monitor_command(monitor, "device_add usb-mouse,id=mouse1,bus=xhci0.0")
                time.sleep(0.6)
                wait_devices(connection, process,
                             [b"keyboard ready", b"mouse ready"])
                reports = mouse_report(monitor, memory, reports)
                send_version(monitor, connection, process)
                after = capture_record(monitor, memory)
                before_pages = before["allocator_next"] // 4096 - before["free_page_count"]
                after_pages = after["allocator_next"] // 4096 - after["free_page_count"]
                if (after["exception"] != 0 or after_pages != before_pages or
                    after["xhci_dma"] != before["xhci_dma"] or reports <= before["xhci_reports"]):
                    raise AssertionError(f"dual HID recovery leaked resources: {before}, {after}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} dual-HID xHCI test passed")


if __name__ == "__main__":
    main()
