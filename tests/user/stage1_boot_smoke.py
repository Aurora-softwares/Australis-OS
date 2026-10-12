#!/usr/bin/env python3
"""Exercise stage 1 AUEX start data, methods, arrays, exit, and cleanup."""

from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import PROMPT, capture_record, read_until  # noqa: E402


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    with tempfile.TemporaryDirectory(prefix="australis-userland-stage1-") as temporary:
        directory = Path(temporary)
        serial = directory / "serial.sock"
        monitor = directory / "monitor.sock"
        launch = [qemu, "-machine", "q35", "-m", "256M",
                  "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
                  "-cdrom", iso, "-display", "none", "-net", "none", "-no-reboot",
                  "-serial", f"unix:{serial},server=on,wait=off",
                  "-monitor", f"unix:{monitor},server=on,wait=off"]
        if transport == "ahci":
            launch += ["-device", "ich9-ahci,id=ahci0", "-drive",
                       f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
                       "-device", "ide-hd,drive=sata0,bus=ahci0.0"]
        else:
            launch += ["-drive", f"if=none,id=nvme0,format=raw,readonly=on,file={iso}",
                       "-device", "nvme,serial=australis,drive=nvme0"]
        process = subprocess.Popen(launch, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 15
            while not serial.exists():
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(serial))
                read_until(connection, PROMPT, 90, process)
                before = capture_record(str(monitor), str(directory / "before.bin"))
                connection.sendall(b'userland first "two words"\r')
                starter = read_until(connection, b"\n" + PROMPT, 45, process)
                for expected in (b"first\r\n", b"two words\r\n"):
                    if expected not in starter:
                        raise AssertionError(f"userland starter missing {expected!r}: {starter!r}")
                starter_record = capture_record(str(monitor), str(directory / "starter.bin"))
                if (starter_record["user_state"] != 2 or
                        starter_record["user_exit"] != 0 or
                        starter_record["user_fault"] != 0 or
                        starter_record["user_descriptors"] != 0):
                    raise AssertionError(f"userland starter failed: {starter_record}")
                commands = (
                    b'stage1-app /hello.txt -an "two words"',
                    b"run /stage1-app.exec /hello.txt -an 'two words'",
                    b"stage1-app /hello.txt -an two\\ words",
                    b'stage1-app /hello.txt -an "two words"',
                )
                for command in commands:
                    connection.sendall(command + b"\r")
                    answer = read_until(connection, b"\n" + PROMPT, 45, process)
                    for expected in (b"/hello.txt\r\n", b"-an\r\n",
                                     b"two words\r\n", b"stage1-ok\r\n",
                                     b"User program exited with an error.\r\n"):
                        if expected not in answer:
                            raise AssertionError(f"{command!r} missing {expected!r}: {answer!r}")
                after = capture_record(str(monitor), str(directory / "after.bin"))
                if (after["user_state"] != 2 or after["user_exit"] != 23 or
                        after["user_fault"] != 0 or
                        after["user_runs"] != before["user_runs"] + len(commands) + 1 or
                        after["user_pid"] != before["user_pid"] + len(commands) + 1 or
                        after["user_descriptors"] != 0 or
                        after["allocator_next"] != before["allocator_next"] or
                        after["allocator_next"] != after["transient_floor"] or
                        after["free_page_count"] != before["free_page_count"] or
                        after["mapping_error"] != 0 or after["memory_error"] != 0 or
                        after["exception"] != 0):
                    raise AssertionError(f"stage 1 resource/state mismatch: {before}; {after}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} userland stage 1 passed")


if __name__ == "__main__":
    main()
