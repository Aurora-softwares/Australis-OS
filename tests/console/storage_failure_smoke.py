#!/usr/bin/env python3
"""Inject a persistent file-sector EIO and verify the live shell recovers."""

from pathlib import Path
import os
import socket
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "storage"))
from controller_boot_smoke import hyfs_partition
from serial_boot_smoke import PROMPT, capture_record, command, read_until


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    first_lba, _ = hyfs_partition(iso)
    # Sorted root entries place fault.txt at HyFS block 2. This sector is
    # untouched by the boot self-test, then read by the shell command below.
    sector = first_lba + 2
    with tempfile.TemporaryDirectory(prefix="australis-fault-") as temporary:
        config = os.path.join(temporary, "blkdebug.conf")
        Path(config).write_text(
            f'[inject-error]\nevent = "read_aio"\nsector = "{sector}"\nerrno = "5"\n'
        )
        serial_path = os.path.join(temporary, "serial.sock")
        monitor_path = os.path.join(temporary, "monitor.sock")
        memory_path = os.path.join(temporary, "ram.bin")
        disk = f"blkdebug:{config}:{iso}"
        arguments = [
            qemu, "-machine", "q35", "-m", "256M",
            "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
            "-cdrom", iso, "-display", "none", "-net", "none", "-no-reboot",
            "-monitor", f"unix:{monitor_path},server=on,wait=off",
            "-serial", f"unix:{serial_path},server=on,wait=off",
        ]
        if transport == "ahci":
            arguments += ["-device", "ich9-ahci,id=ahci0",
                          "-drive", f"if=none,id=sata0,format=raw,snapshot=on,file={disk}",
                          "-device", "ide-hd,drive=sata0,bus=ahci0.0"]
        else:
            arguments += ["-drive", f"if=none,id=nvme0,format=raw,readonly=on,file={disk}",
                          "-device", "nvme,serial=australis,drive=nvme0"]
        process = subprocess.Popen(arguments, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 10
            while not os.path.exists(serial_path):
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() > deadline:
                    raise TimeoutError("QEMU serial socket missing")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(serial_path)
                read_until(connection, PROMPT, 60, process)
                before = capture_record(monitor_path, memory_path)
                connection.sendall(b"cat /fault.txt\r")
                failed_output = read_until(connection, PROMPT, 30, process)
                if b"File read failed.\r\n" not in failed_output or b"This file is used" in failed_output:
                    raise AssertionError(f"failed read exposed data or silenced the error: {failed_output!r}")
                failed = capture_record(monitor_path, memory_path)
                if (failed["storage_cause"] == 0 or failed["storage_state"] != 4 or
                        failed["storage_irqs"] <= before["storage_irqs"] or failed["exception"] != 0):
                    raise AssertionError(f"missing failed-completion diagnostics: {failed}")
                command(connection, process, b"version", b"version: 0.0.1\r\n")
                hello = (Path(__file__).resolve().parents[2] / "rootfs" / "hello.txt").read_bytes()
                command(connection, process, b"cat /hello.txt", hello)
                after = capture_record(monitor_path, memory_path)
                if (after["storage_cause"] != 0 or after["storage_state"] != 0 or
                        after["storage_irqs"] <= failed["storage_irqs"] or
                        after["allocator_next"] != before["allocator_next"] or
                        after["memory_error"] != 0 or after["dynamic_mapping_base"] != 0):
                    raise AssertionError(f"shell or allocator did not recover: {after}")
            print(f"Australis {transport.upper()} failed-completion QEMU test passed")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    main()
