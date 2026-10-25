
#!/usr/bin/env python3
"""Verify unprivileged AUEX processes cannot access retained display APIs."""

from pathlib import Path
from tempfile import TemporaryDirectory
import socket
import subprocess
import sys
import time

sys.path.insert(
    0, str(Path(__file__).resolve().parents[1] / "console")
)
from serial_boot_smoke import read_until


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]

    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")

    iso = str(Path(iso).resolve())

    with TemporaryDirectory(prefix="australis-retained-denial-") as tmp:
        serial = Path(tmp) / "serial.sock"

        command = [
            qemu, "-machine", "q35", "-m", "256M",
            "-drive",
            f"if=pflash,format=raw,readonly=on,file={firmware}",
            "-cdrom", iso,
            "-display", "none",
            "-net", "none",
            "-no-reboot",
            "-serial", f"unix:{serial},server=on,wait=off",
            "-monitor", "none",
        ]

        if transport == "ahci":
            command += [
                "-device", "ich9-ahci,id=ahci0",
                "-drive",
                f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
                "-device", "ide-hd,drive=sata0,bus=ahci0.0",
            ]
        else:
            command += [
                "-drive",
                f"if=none,id=nvme0,format=raw,readonly=on,file={iso}",
                "-device", "nvme,serial=australis,drive=nvme0",
            ]

        process = subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )

        try:
            deadline = time.monotonic() + 30

            while not serial.exists():
                if process.poll() is not None:
                    raise RuntimeError(
                        process.stderr.read().decode(errors="replace")
                    )
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open serial socket")
                time.sleep(0.05)

            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(serial))

                read_until(connection, b"australis> ", 90, process)

                connection.sendall(
                    b"run /System/Bin/retained-permission.exec\r"
                )

                response = read_until(
                    connection, b"\naustralis> ", 45, process
                )

                if (
                    b"retained-permission: denied" not in response
                    or b"retained-permission: FAILED" in response
                    or b"shell: program fault:" in response
                    or b"shell: exit status " in response
                ):
                    raise AssertionError(
                        f"Retained API denial failed: {response[-3000:]!r}"
                    )

                # Verify the shell survived the denied operations.
                connection.sendall(b"version\r")
                response = read_until(
                    connection, b"australis> ", 20, process
                )

                if b"Version: 0.0.1" not in response:
                    raise AssertionError(
                        "Shell stopped after permission denial"
                    )
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

    print(
        f"Australis {transport.upper()} retained compositor "
        "permission denial passed"
    )


if __name__ == "__main__":
    main()
