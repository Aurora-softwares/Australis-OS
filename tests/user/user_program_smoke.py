#!/usr/bin/env python3
"""Run AUEX terminal/file syscalls and isolation recovery under QEMU."""

import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import PROMPT, capture_record, monitor_command, read_until


def shell(connection, process, command, timeout=30):
    connection.sendall(command + b"\r")
    return read_until(connection, b"\n" + PROMPT, timeout, process)


def run_demo(connection, process, path):
    connection.sendall(b"run " + path + b"\r")
    opening = read_until(connection, b"user> ", 30, process)
    if b"Starting user program.\r\n" not in opening:
        raise AssertionError(f"user loader did not start: {opening!r}")
    connection.sendall(b"ab\x08C\r")
    result = read_until(connection, b"\n" + PROMPT, 45, process)
    if (b"input: aC\r\n" not in result or
            b"file: Hello from Australis HyFS." not in result or
            b"User program exited cleanly.\r\n" not in result):
        raise AssertionError(f"user terminal/file program failed: {result!r}")


def main():
    if len(sys.argv) != 5:
        raise SystemExit("usage: user_program_smoke.py QEMU OVMF ISO ahci|nvme")
    qemu, ovmf, iso, transport = sys.argv[1:]
    if transport not in ("ahci", "nvme"):
        raise SystemExit("transport must be ahci or nvme")
    iso = str(Path(iso).resolve())

    with tempfile.TemporaryDirectory(prefix="australis-user-") as temporary:
        serial_path = os.path.join(temporary, "serial.sock")
        monitor_path = os.path.join(temporary, "monitor.sock")
        memory_path = os.path.join(temporary, "memory.bin")
        arguments = [qemu, "-machine", "q35", "-m", "256M", "-drive",
            f"if=pflash,format=raw,readonly=on,file={ovmf}", "-cdrom", iso,
            "-device", "qemu-xhci,id=xhci0", "-drive",
            f"if=none,id=usbdrive0,format=raw,readonly=on,file={iso}",
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

                hello_program = shell(connection, process, b"run /hello_world.exec", 30)
                if (b"Hello, World!\r\n" not in hello_program or
                        b"User program exited cleanly.\r\n" not in hello_program):
                    raise AssertionError(
                        f"compiler generated hello program failed: {hello_program!r}")

                # Canonical traversal crosses into /usb and back to the boot
                # root. Repeated separators and dot components stay valid.
                traversed = shell(connection, process, b"cat /usb/.././hello.txt", 30)
                if b"Hello from Australis HyFS." not in traversed:
                    raise AssertionError(f"nested root traversal failed: {traversed!r}")
                removable = shell(connection, process, b"cat //usb/./hello.txt", 45)
                if b"Hello from Australis HyFS." not in removable:
                    raise AssertionError(f"nested removable traversal failed: {removable!r}")

                run_demo(connection, process, b"/user-demo.exec")
                run_demo(connection, process, b"/usb/../user-demo.exec")
                after_demo = capture_record(monitor_path, memory_path)
                if (after_demo["user_state"] != 2 or after_demo["user_exit"] != 0 or
                        after_demo["user_fault"] != 0 or after_demo["user_runs"] != 3 or
                        after_demo["user_instructions"] < 10 or
                        after_demo["allocator_next"] != before["allocator_next"]):
                    raise AssertionError(
                        f"user process did not exit and reclaim memory: before={before}, after={after_demo}")

                faulted = shell(connection, process, b"run /user-fault.exec", 30)
                if (b"requesting protected write\r\n" not in faulted or
                        b"User program blocked from kernel memory.\r\n" not in faulted):
                    raise AssertionError(f"protected write was not blocked: {faulted!r}")
                after_fault = capture_record(monitor_path, memory_path)
                if (after_fault["user_state"] != 3 or after_fault["user_fault"] != 3 or
                        after_fault["user_runs"] != 4 or
                        after_fault["allocator_next"] != before["allocator_next"]):
                    raise AssertionError(f"fault cleanup changed kernel state: {after_fault}")

                invalid = shell(connection, process, b"run /fault.txt")
                if b"Invalid user executable.\r\n" not in invalid:
                    raise AssertionError(f"invalid executable was accepted: {invalid!r}")
                process_list = shell(connection, process, b"ps")
                if b"pid 1: faulted\r\n" not in process_list:
                    raise AssertionError(f"process inspection lost last state: {process_list!r}")

                # Remove the live USB device after a user fault. COM1 must
                # remain the recovery terminal while deferred xHCI work runs.
                monitor_command(monitor_path, "device_del usb0")
                time.sleep(0.5)
                recovered = shell(connection, process, b"version", 30)
                if b"version: 0.0.1\r\n" not in recovered:
                    raise AssertionError(f"serial recovery failed after USB removal: {recovered!r}")
                final = capture_record(monitor_path, memory_path)
                if (final["exception"] != 0 or final["ring_dropped"] != 0 or
                        final["event_dropped"] != 0 or final["memory_error"] != 0 or
                        final["allocator_next"] != before["allocator_next"] or
                        final["user_runs"] != 5):
                    raise AssertionError(f"stage 5 left an unhealthy kernel: {final}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait(timeout=5)
    print(f"Australis {transport.upper()} user program QEMU test passed")


if __name__ == "__main__":
    main()
