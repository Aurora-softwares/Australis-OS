#!/usr/bin/env python3
"""Exercise the source-built cat command through PATH on a live HyFS root."""

from pathlib import Path
import socket
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


def contains_file(output, file_path):
    contents = file_path.read_bytes()
    if contents not in output and contents.replace(b"\n", b"\r\n") not in output:
        raise AssertionError(f"cat did not print all of {file_path.name}: {output[-500:]!r}")


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    rootfs = Path(__file__).resolve().parents[2] / "rootfs"
    with tempfile.TemporaryDirectory(prefix="australis-cat-") as temporary:
        serial_path = str(Path(temporary) / "serial.sock")
        monitor_path = str(Path(temporary) / "monitor.sock")
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
            while not Path(serial_path).exists():
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as serial:
                serial.connect(serial_path)
                read_until(serial, PROMPT, 90, process)
                before = capture_record(monitor_path, str(Path(temporary) / "before.bin"))

                hello = run(serial, process, b"run cat /hello.txt")
                contains_file(hello, rootfs / "hello.txt")
                long_file = run(serial, process, b"run cat /readme.txt")
                contains_file(long_file, rootfs / "readme.txt")
                empty = run(serial, process, b"run cat /empty.txt")
                if b"cat: " in empty or b"User program exited with an error." in empty:
                    raise AssertionError(f"empty file was not clean EOF: {empty!r}")
                missing = run(serial, process, b"run cat /missing.txt")
                if (b"cat: open failed (status):" not in missing or
                        b"User program exited with an error." not in missing):
                    raise AssertionError(f"missing-file error was lost: {missing!r}")

                after = capture_record(monitor_path, str(Path(temporary) / "after.bin"))
                if (after["user_runs"] != before["user_runs"] + 4 or
                        after["user_state"] != 2 or after["user_exit"] != 4 or
                        after["user_fault"] != 0 or after["user_descriptors"] != 0 or
                        after["allocator_next"] != before["allocator_next"] or
                        after["free_page_count"] != before["free_page_count"] or
                        after["mapping_error"] != 0 or after["memory_error"] != 0):
                    raise AssertionError(f"cat leaked resources or lost status: {before}; {after}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} cat.exec passed")


if __name__ == "__main__":
    main()
