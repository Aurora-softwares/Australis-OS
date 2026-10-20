#!/usr/bin/env python3
"""Exercise keyboard and read-only storage on two xHCI root ports."""

from pathlib import Path
import os
import socket
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import PROMPT, capture_record, monitor_command, read_until


def shell(connection, process, command):
    connection.sendall(command + b"\r")
    return read_until(connection, b"\n" + PROMPT, 30, process)


def wait_devices(connection, process, expected):
    response = b""
    for _ in range(8):
        response = shell(connection, process, b"devices")
        if all(marker in response for marker in expected):
            return response
        time.sleep(0.25)
    raise AssertionError(f"xHCI device recovery failed: {response!r}")


def send_version(monitor, connection, process):
    for key in "version":
        monitor_command(monitor, f"sendkey {key} 20")
        time.sleep(0.04)
    monitor_command(monitor, "sendkey ret 20")
    typed = read_until(connection, b"\n" + PROMPT, 20, process)
    if b"version: 0.0.1" not in typed:
        raise AssertionError(f"keyboard stopped alongside storage: {typed!r}")


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    iso = str(Path(iso).resolve())
    hello = (Path(__file__).resolve().parents[2] / "rootfs" / "hello.txt").read_bytes()
    with tempfile.TemporaryDirectory(prefix="australis-xhci-multi-") as directory:
        serial = os.path.join(directory, "serial.sock")
        monitor = os.path.join(directory, "monitor.sock")
        memory = os.path.join(directory, "memory.bin")
        command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
                   f"if=pflash,format=raw,readonly=on,file={firmware}",
                   "-cdrom", iso, "-device", "qemu-xhci,id=xhci0",
                   "-device", "usb-kbd,id=kbd0,bus=xhci0.0",
                   "-drive", f"if=none,id=usbdrive0,format=raw,readonly=on,file={iso}",
                   "-device", "usb-storage,id=usb0,drive=usbdrive0,bus=xhci0.0",
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
                devices = shell(connection, process, b"devices")
                mounts = shell(connection, process, b"mounts")
                content = shell(connection, process, b"cat /usb/hello.txt")
                record = capture_record(monitor, memory)
                storage_index = 0 if b"usb0: mass-storage ready" in devices else 1
                keyboard_index = 1 - storage_index
                if (f"usb{storage_index}: mass-storage ready".encode() not in devices or
                    f"usb{keyboard_index}: keyboard ready".encode() not in devices or
                    f"/usb: hyfs usb{storage_index}".encode() not in mounts or
                    hello not in content or
                    record["exception"] != 0):
                    raise AssertionError(f"two root devices failed: devices={devices!r}, "
                                         f"mounts={mounts!r}, file={content!r}, record={record}")
                send_version(monitor, connection, process)

                monitor_command(monitor, "device_del kbd0")
                time.sleep(0.45)
                wait_devices(connection, process, [b"mass-storage ready"])
                if hello not in shell(connection, process, b"cat /usb/hello.txt"):
                    raise AssertionError("removing keyboard disrupted USB storage")
                monitor_command(monitor, "device_add usb-kbd,id=kbd1,bus=xhci0.0")
                time.sleep(0.6)
                wait_devices(connection, process,
                             [b"keyboard ready", b"mass-storage ready"])
                send_version(monitor, connection, process)

                monitor_command(monitor, "device_del usb0")
                time.sleep(0.45)
                wait_devices(connection, process, [b"keyboard ready"])
                missing = shell(connection, process, b"cat /usb/hello.txt")
                if hello in missing:
                    raise AssertionError("removed USB storage remained readable")
                monitor_command(monitor,
                                f"drive_add 0 if=none,id=usbdrive1,format=raw,readonly=on,file={iso}")
                monitor_command(monitor,
                                "device_add usb-storage,id=usb1,drive=usbdrive1,bus=xhci0.0")
                time.sleep(0.6)
                wait_devices(connection, process,
                             [b"keyboard ready", b"mass-storage ready"])
                if hello not in shell(connection, process, b"cat /usb/hello.txt"):
                    raise AssertionError("USB storage did not recover after reconnect")
                send_version(monitor, connection, process)
                after = capture_record(monitor, memory)
                before_pages = record["allocator_next"] // 4096 - record["free_page_count"]
                after_pages = after["allocator_next"] // 4096 - after["free_page_count"]
                if (after["exception"] != 0 or after["xhci_recoveries"] < 2 or
                    after_pages != before_pages or after["xhci_dma"] != record["xhci_dma"]):
                    raise AssertionError(f"two-device recovery leaked resources: {record}, {after}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} two-root xHCI test passed")


if __name__ == "__main__":
    main()
