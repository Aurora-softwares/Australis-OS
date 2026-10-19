#!/usr/bin/env python3
"""Exercise the packaged system and memory information applications."""

from pathlib import Path
import socket
import re
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import PROMPT, capture_record, read_until  # noqa: E402


def run(connection, process, command):
    connection.sendall(command + b"\r")
    return read_until(connection, b"\n" + PROMPT, 45, process)


def require(output, expected, command):
    if expected not in output:
        raise AssertionError(f"{command!r} missing {expected!r}: {output!r}")


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    with tempfile.TemporaryDirectory(prefix="australis-system-info-") as temporary:
        directory = Path(temporary)
        serial_path = directory / "serial.sock"
        monitor_path = directory / "monitor.sock"
        command = [
            qemu, "-machine", "q35", "-m", "256M",
            "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
            "-cdrom", iso, "-display", "none", "-net", "none", "-no-reboot",
            "-serial", f"unix:{serial_path},server=on,wait=off",
            "-monitor", f"unix:{monitor_path},server=on,wait=off",
        ]
        if transport == "ahci":
            command += [
                "-device", "ich9-ahci,id=ahci0",
                "-drive", f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
                "-device", "ide-hd,drive=sata0,bus=ahci0.0",
            ]
        else:
            command += [
                "-drive", f"if=none,id=nvme0,format=raw,readonly=on,file={iso}",
                "-device", "nvme,serial=australis,drive=nvme0",
            ]
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 15
            while not serial_path.exists():
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(serial_path))
                read_until(connection, PROMPT, 90, process)
                before = capture_record(str(monitor_path), str(directory / "before.bin"))

                system = run(connection, process, b"run sys-info")
                require(system, b"Australis System Information\r\n", "sys-info")
                require(system, b"System information API:\r\n5\r\n", "sys-info")
                require(system, b"Boot information ABI:\r\n7\r\n", "sys-info")
                for label, value in (
                    (b"Framebuffer width", before["framebuffer_width"]),
                    (b"Framebuffer height", before["framebuffer_height"]),
                    (b"Framebuffer stride in pixels", before["framebuffer_stride"]),
                    (b"Framebuffer pixel format (0 RGB, 1 BGR)", before["framebuffer_format"]),
                    (b"Framebuffer bits per pixel", 32),
                    (b"Framebuffer mode flags (1 valid, 2 fixed)", 3),
                ):
                    require(system, label + b":\r\n" + str(value).encode() + b"\r\n", "sys-info")
                controller = b"1" if transport == "ahci" else b"2"
                require(system,
                        b"Block controller (1 AHCI, 2 NVMe):\r\n" + controller + b"\r\n",
                        "sys-info")

                memory = run(connection, process, b"run mem-info")
                require(memory, b"Australis Memory Information\r\n", "mem-info")
                require(memory, b"Page size in bytes:\r\n4096\r\n", "mem-info")
                require(memory, b"Memory runtime status:\r\n0\r\n", "mem-info")
                require(memory, b"Page table audit status:\r\n0\r\n", "mem-info")

                device = run(connection, process, b"devices")
                kind = b"AHCI" if transport == "ahci" else b"NVMe"
                require(device, b"boot0: " + kind + b" storage ready\r\n", "devices")
                driver = run(connection, process, b"drivers")
                require(driver, b"Active kernel drivers:\r\n", "drivers")
                require(driver, b"serial: COM1 ready\r\n", "drivers")
                require(driver, b"storage: " + kind + b" (MSI", "drivers")
                require(driver, b"usb: unavailable\r\n", "drivers")
                require(driver, b"timer: calibrated\r\n", "drivers")
                usage = run(connection, process, b"mem")
                require(usage, b"Memory usage:\r\n", "mem")
                require(usage, b"page size: 4096\r\n", "mem")
                require(usage, b"memory runtime status: 0\r\n", "mem")
                pages = run(connection, process, b"pages")
                if re.search(rb"available: [1-9][0-9]*\r\n", pages) is None:
                    raise AssertionError(f"pages omitted allocator capacity: {pages!r}")
                require(pages, b"allocator status: 0\r\n", "pages")
                memory_map = run(connection, process, b"memmap")
                if re.search(rb"descriptors: [1-9][0-9]*\r\n", memory_map) is None:
                    raise AssertionError(f"memmap omitted descriptor count: {memory_map!r}")
                require(memory_map, b"Boot D for physical ranges.\r\n", "memmap")

                after = capture_record(str(monitor_path), str(directory / "after.bin"))
                if (after["user_runs"] != before["user_runs"] + 4 or
                        after["user_state"] != 2 or after["user_exit"] != 0 or
                        after["user_fault"] != 0 or after["user_descriptors"] != 0 or
                        after["allocator_next"] != before["allocator_next"] or
                        after["free_page_count"] != before["free_page_count"] or
                        after["mapping_error"] != 0 or after["memory_error"] != 0):
                    raise AssertionError(
                        f"information apps leaked resources or lost status: {before}; {after}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} information applications passed")


if __name__ == "__main__":
    main()
