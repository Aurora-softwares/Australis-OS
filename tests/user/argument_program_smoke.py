#!/usr/bin/env python3
"""Check AUEX argv delivery through bare and explicit shell commands."""

from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import PROMPT, capture_record, read_until  # noqa: E402


def command(connection, process, value, expected):
    connection.sendall(value + b"\r")
    answer = read_until(connection, b"\n" + PROMPT, 45, process)
    if expected not in answer:
        raise AssertionError(f"{value!r} did not produce {expected!r}: {answer!r}")
    return answer


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    with tempfile.TemporaryDirectory(prefix="australis-argv-") as temporary:
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
                command(connection, process, b"argv-check", b"no-args\r\n")
                command(connection, process,
                        b'argv-check /hello.txt -an --argument "two words"',
                        b"arguments-ok\r\n")
                command(connection, process,
                        b"run /argv-check.exec /path/with\\ space -an --argument 'two words'",
                        b"arguments-ok\r\n")
                command(connection, process, b"inspector /hello.txt",
                        b"Australis File Inspector\r\n/hello.txt\r\n")
                inspected = command(connection, process,
                                    b"inspector /System/Bin/inspector.exec",
                                    b"Target: Australis bytecode\r\n")
                image = (Path(iso).parent / "rootfs" / "inspector.exec").read_bytes()
                if b"Format version:\r\n1\r\n" not in inspected:
                    raise AssertionError(f"AUEX version missing: {inspected!r}")
                for title, offset in ((b"Code bytes", 8),
                                      (b"Initialized data bytes", 12),
                                      (b"Data capacity", 16),
                                      (b"Entry offset", 20),
                                      (b"Stored code CRC32", 24),
                                      (b"Stored data CRC32", 28)):
                    value = struct.unpack_from("<I", image, offset)[0]
                    expected = title + b":\r\n" + str(value).encode() + b"\r\n"
                    if expected not in inspected:
                        raise AssertionError(f"AUEX {title!r} mismatch: {inspected!r}")
                listing = command(connection, process, b"inspector /System",
                                  b"Directory entries:\r\n")
                if b"hexviewer.exec\r\n" not in listing:
                    raise AssertionError(f"nested directory listing missing: {listing!r}")
                command(connection, process, b'argv-check "unterminated',
                        b"Invalid command line.\r\n")
                command(connection, process, b"argv-check " + b"x " * 17,
                        b"Invalid command line.\r\n")
                state = capture_record(str(monitor), str(directory / "memory.bin"))
                if (state["user_state"] != 2 or state["user_exit"] != 0 or
                        state["user_fault"] != 0 or state["user_runs"] != 6):
                    raise AssertionError(f"argument execution failed: {state}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} AUEX arguments passed")


if __name__ == "__main__":
    main()
