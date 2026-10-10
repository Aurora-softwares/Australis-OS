#!/usr/bin/env python3
"""Exercise live xHCI MSC BOT, removable HyFS reads, and recovery in QEMU."""

import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import (PROMPT, capture_record, command, monitor_command,
                               read_until)


def shell(connection, process, text, timeout=30):
    connection.sendall(text + b"\r")
    return read_until(connection, b"\n" + PROMPT, timeout, process)


def read_prompts(connection, process, count, timeout):
    deadline = time.monotonic() + timeout
    received = bytearray()
    while received.count(PROMPT) < count:
        received.extend(read_until(connection, PROMPT, deadline - time.monotonic(), process))
    return bytes(received)


def wait_for_storage(connection, process, cycle, monitor_path, memory_path):
    response = b""
    for _ in range(8):
        response = shell(connection, process, b"devices", 40)
        if b"usb0: mass-storage ready\r\n" in response:
            return
        time.sleep(0.25)
    record = capture_record(monitor_path, memory_path)
    raise AssertionError(
        f"USB storage did not recover in cycle {cycle}: response={response!r}, record={record}")


def main():
    if len(sys.argv) != 5:
        raise SystemExit("usage: xhci_storage_smoke.py QEMU OVMF ISO ahci|nvme")
    qemu, ovmf, iso, transport = sys.argv[1:]
    if transport not in ("ahci", "nvme"):
        raise SystemExit("transport must be ahci or nvme")
    iso = str(Path(iso).resolve())
    root = Path(__file__).resolve().parents[2]
    hello = (root / "rootfs" / "hello.txt").read_bytes()
    multi = (root / "rootfs" / "usb-multi.txt").read_bytes()
    if len(multi) <= 512:
        raise AssertionError("USB storage fixture must span multiple sectors")

    with tempfile.TemporaryDirectory(prefix="australis-xhci-storage-") as temporary:
        serial_path = os.path.join(temporary, "serial.sock")
        monitor_path = os.path.join(temporary, "monitor.sock")
        memory_path = os.path.join(temporary, "memory.bin")
        arguments = [qemu, "-machine", "q35", "-m", "256M", "-drive",
            f"if=pflash,format=raw,readonly=on,file={ovmf}", "-cdrom", iso,
            "-device", "qemu-xhci,id=xhci0",
            "-drive", f"if=none,id=usbdrive0,format=raw,readonly=on,file={iso}",
            "-device", "usb-storage,id=usb0,drive=usbdrive0,bus=xhci0.0",
            "-net", "none", "-display", "none", "-no-reboot",
            "-serial", f"unix:{serial_path},server=on,wait=off",
            "-monitor", f"unix:{monitor_path},server=on,wait=off"]
        if transport == "ahci":
            arguments += ["-device", "ich9-ahci,id=ahci0", "-drive",
                f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
                "-device", "ide-hd,drive=sata0,bus=ahci0.0"]
        else:
            arguments += ["-drive", f"if=none,id=nvme0,format=raw,readonly=on,file={iso}",
                "-device", "nvme,serial=australis,drive=nvme0"]

        process = subprocess.Popen(arguments, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
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
                if (before["exception"] != 0 or before["xhci_state"] != 20 or
                    before["xhci_cause"] != 0 or before["usb_kind"] != 2 or
                    before["usb_sector_size"] != 512 or before["usb_sector_count"] < 6 or
                    before["usb_gpt_status"] != 0 or before["usb_mount_status"] != 0 or
                    before["xhci_dma"] == 0 or before["device_vector"] != 50 or
                    before["device_irqs"] == 0):
                    raise AssertionError(f"xHCI mass storage did not initialize: {before}")

                devices = shell(connection, process, b"devices")
                mounts = shell(connection, process, b"mounts")
                listing = shell(connection, process, b"ls /usb")
                if (b"usb0: mass-storage ready\r\n" not in devices or
                    b"/usb: hyfs usb0\r\n" not in mounts or
                    b"/usb/usb-multi.txt\r\n" not in listing):
                    raise AssertionError("removable volume was not exposed by the shell")
                first_read = shell(connection, process, b"cat /usb/usb-multi.txt", 45)
                if multi not in first_read:
                    raise AssertionError("multi-sector USB file was not returned intact")

                # Limit USB reads briefly and queue another COM1 command while
                # normal context is displaying the multi-sector file.
                monitor_command(monitor_path, "block_set_io_throttle usbdrive0 0 0 0 0 5 0")
                connection.sendall(b"cat /usb/usb-multi.txt\r")
                time.sleep(0.1)
                connection.sendall(b"version\r")
                delayed = read_prompts(connection, process, 2, 45)
                monitor_command(monitor_path, "block_set_io_throttle usbdrive0 0 0 0 0 0 0")
                if multi not in delayed or b"version: 0.0.1\r\n" not in delayed:
                    raise AssertionError("delayed USB read lost data or queued serial input")

                stable_pages = None
                for cycle in range(3):
                    monitor_command(monitor_path, f"device_del usb{cycle}")
                    time.sleep(0.45)
                    unavailable = shell(connection, process, b"devices")
                    failed = shell(connection, process, b"cat /usb/usb-multi.txt", 20)
                    if (b"removed or unavailable" not in unavailable or
                        b"File read failed.\r\n" not in failed or
                        b"USB stage 4 sector stream" in failed):
                        raise AssertionError(f"removal exposed partial data in cycle {cycle}: {failed!r}")
                    command(connection, process, f"echo serial {cycle}".encode(),
                            f"serial {cycle}\r\n".encode())

                    drive = f"usbdrive{cycle + 1}"
                    monitor_command(monitor_path,
                        f"drive_add 0 if=none,id={drive},format=raw,readonly=on,file={iso}")
                    monitor_command(monitor_path,
                        f"device_add usb-storage,id=usb{cycle + 1},drive={drive},bus=xhci0.0")
                    time.sleep(0.6)
                    wait_for_storage(connection, process, cycle, monitor_path, memory_path)
                    restored = shell(connection, process, b"cat /usb/usb-multi.txt", 45)
                    if multi not in restored:
                        raise AssertionError(f"USB read did not recover in cycle {cycle}")
                    record = capture_record(monitor_path, memory_path)
                    pages = (record["allocator_next"] // 4096 - record["free_page_count"],
                             record["xhci_dma"], record["dynamic_mapping_base"])
                    if stable_pages is None:
                        stable_pages = pages
                    elif pages != stable_pages:
                        raise AssertionError(
                            f"USB recovery leaked pages: first={stable_pages}, now={pages}")

                root_read = shell(connection, process, b"cat /hello.txt")
                after = capture_record(monitor_path, memory_path)
                if hello not in root_read:
                    raise AssertionError("boot root stopped working after USB recovery")
                if (after["exception"] != 0 or after["xhci_state"] != 20 or
                    after["xhci_cause"] != 0 or after["xhci_recoveries"] < 3 or
                    after["xhci_hotplug"] < 3 or after["usb_reads"] <= before["usb_reads"] or
                    after["device_irqs"] <= before["device_irqs"] or
                    after["xhci_transfers"] <= before["xhci_transfers"] or
                    after["xhci_dma"] != before["xhci_dma"] or
                    after["allocator_next"] // 4096 - after["free_page_count"] !=
                    before["allocator_next"] // 4096 - before["free_page_count"] or
                    after["dynamic_mapping_base"] != before["dynamic_mapping_base"] or
                    after["ring_dropped"] != 0 or after["event_dropped"] != 0 or
                    after["device_vector"] != 50):
                    raise AssertionError(f"xHCI storage recovery lost state: before={before}, after={after}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait(timeout=5)
    print(f"Australis {transport.upper()} xHCI storage QEMU test passed")


if __name__ == "__main__":
    main()
