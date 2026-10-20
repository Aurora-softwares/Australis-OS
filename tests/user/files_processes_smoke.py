#!/usr/bin/env python3
"""Check external file/process commands and KMon mount reporting in QEMU."""

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


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    with tempfile.TemporaryDirectory(prefix="australis-files-processes-") as temporary:
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

                mounts = run(connection, process, b"mounts")
                if b"/: hyfs boot0\r\n" not in mounts:
                    raise AssertionError(f"boot root not reported: {mounts!r}")
                root = run(connection, process, b"ls /")
                for entry in (b"hello.txt\r\n", b"readme.txt\r\n", b"ls.exec\r\n"):
                    if entry not in root:
                        raise AssertionError(f"ls / missing {entry!r}: {root!r}")
                system = run(connection, process, b"ls /System")
                if b"Core\r\n" not in system or b"hexviewer.exec\r\n" not in system:
                    raise AssertionError(f"ls /System failed: {system!r}")
                single = run(connection, process, b"ls /hello.txt")
                if b"/hello.txt\r\n" not in single:
                    raise AssertionError(f"ls file failed: {single!r}")
                contents = run(connection, process, b"cat /hello.txt")
                if b"Hello from Australis HyFS." not in contents:
                    raise AssertionError(f"bare cat did not run cat.exec: {contents!r}")
                missing = run(connection, process, b"ls /missing")
                if (b"ls: stat failed (status):\r\n4\r\n" not in missing or
                        b"User program exited with an error.\r\n" not in missing):
                    raise AssertionError(f"ls missing-file status lost: {missing!r}")

                processes = run(connection, process, b"ps")
                live_pid = before["user_pid"] + 6
                prior_pid = live_pid - 1
                if (f"{live_pid} running (foreground)\r\n".encode() not in processes or
                        f"{prior_pid} exited, status 4\r\n".encode() not in processes or
                        b"program launches: 5\r\n" not in processes):
                    raise AssertionError(f"ps did not report live and prior process: {processes!r}")

                after = capture_record(str(monitor_path), str(directory / "after.bin"))
                if (after["user_runs"] != before["user_runs"] + 6 or
                        after["user_state"] != 2 or after["user_exit"] != 0 or
                        after["user_fault"] != 0 or after["user_descriptors"] != 0 or
                        after["allocator_next"] != before["allocator_next"] or
                        after["free_page_count"] != before["free_page_count"] or
                        after["mapping_error"] != 0 or after["memory_error"] != 0):
                    raise AssertionError(
                        f"file/process commands leaked resources: {before}; {after}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} filesystem/process commands passed")


if __name__ == "__main__":
    main()
