#!/usr/bin/env python3
"""Exercise the live kernel shell over COM1 with an AHCI or NVMe HyFS root."""

from pathlib import Path
import mmap
import os
import socket
import struct
import subprocess
import sys
import tempfile
import time


PROMPT = b"australis> "
BANNER = b"Australis serial console ready. Type help.\r\n"


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
                    "exception": struct.unpack_from("<I", memory, position + 188)[0],
                    "last_vector": struct.unpack_from("<I", memory, position + 184)[0],
                    "serial_flags": struct.unpack_from("<I", memory, position + 1140)[0],
                    "serial_irqs": struct.unpack_from("<I", memory, position + 1148)[0],
                    "memory_error": struct.unpack_from("<I", memory, position + 1160)[0],
                    "mapping_error": struct.unpack_from("<I", memory, position + 1164)[0],
                    "transient_floor": struct.unpack_from("<Q", memory, position + 1152)[0],
                    "free_page_head": struct.unpack_from("<Q", memory, position + 1184)[0],
                    "free_page_count": struct.unpack_from("<Q", memory, position + 1192)[0],
                    "mapping_self_test": struct.unpack_from("<I", memory, position + 1200)[0],
                    "ring_head": struct.unpack_from("<I", memory, position + 1168)[0],
                    "ring_tail": struct.unpack_from("<I", memory, position + 1172)[0],
                    "ring_dropped": struct.unpack_from("<I", memory, position + 1176)[0],
                }
            position += 4


def capture_record(monitor_path, memory_path):
    monitor_command(monitor_path, f'pmemsave 0 0x10000000 "{memory_path}"')
    record = kernel_record(memory_path)
    if record is None:
        raise RuntimeError("QEMU memory did not contain KernelBootInfo")
    return record


def read_until(connection, marker, timeout, process):
    deadline = time.monotonic() + timeout
    received = bytearray()
    while marker not in received:
        if process.poll() is not None:
            raise RuntimeError(f"QEMU exited with status {process.returncode}")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"serial output timed out: {bytes(received[-300:])!r}")
        connection.settimeout(min(remaining, 1))
        try:
            part = connection.recv(4096)
        except socket.timeout:
            continue
        if not part:
            raise RuntimeError(f"serial connection closed: {bytes(received[-300:])!r}")
        received.extend(part)
    return bytes(received)


def command(connection, process, input_bytes, expected_output):
    connection.sendall(input_bytes + b"\r")
    response = read_until(connection, PROMPT, 20, process)
    if expected_output not in response:
        raise AssertionError(
            f"command {input_bytes!r} expected {expected_output!r}; got {response!r}"
        )


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    rootfs = Path(__file__).resolve().parents[2] / "rootfs"
    hello = (rootfs / "hello.txt").read_bytes()
    readme = (rootfs / "readme.txt").read_bytes()
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
                command(connection, process, b"help",
                        b"Commands: help, echo <text>, ls, cat <path>, version\r\n")
                command(connection, process, b"echo hello serial", b"hello serial\r\n")
                command(connection, process, b"echo ab\x08c", b"\r\nac\r\n")
                command(connection, process, b"echo discard\x15echo kept", b"\r\nkept\r\n")
                command(connection, process, b"x" * 257, b"Input line is too long.\r\n")
                command(connection, process, b"ls", b"/hello.txt\r\n/readme.txt\r\n")
                command(connection, process, b"cat /hello.txt", hello)
                command(connection, process, b"cat /readme.txt", readme)
                command(connection, process, b"cat /missing.txt", b"File not found.\r\n")
                command(connection, process, b"cat", b"Usage: cat /filename\r\n")
                command(connection, process, b"unknown", b"Unknown command. Type help.\r\n")
                command(connection, process, b"version", BANNER)
                repeat = 0
                while repeat < 16:
                    command(connection, process, b"cat /hello.txt", hello)
                    repeat += 1
                after = capture_record(monitor_path, memory_path)
                if (after["serial_flags"] != 3 or after["serial_irqs"] <= before["serial_irqs"] or
                        after["ring_head"] != after["ring_tail"] or after["ring_dropped"] != 0 or
                        after["memory_error"] != 0 or after["mapping_error"] != 0 or after["transient_floor"] == 0 or
                        after["free_page_count"] == 0 or after["free_page_head"] == 0 or
                        after["mapping_self_test"] != 0 or
                        after["allocator_next"] != after["transient_floor"] or
                        after["allocator_next"] != before["allocator_next"]):
                    raise AssertionError(f"unexpected hardened kernel state: before={before}, after={after}")
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
