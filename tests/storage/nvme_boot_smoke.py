#!/usr/bin/env python3
"""Boot KERNEL.EFI with QEMU NVMe and verify its published GPT result."""

import mmap
import os
import socket
import struct
import subprocess
import sys
import tempfile
import time


def boot_record(path):
    with open(path, "rb") as image:
        memory = mmap.mmap(image.fileno(), 0, access=mmap.ACCESS_READ)
        position = 0
        while True:
            position = memory.find(b"AUBI", position)
            if position < 0:
                return None
            if struct.unpack_from("<I", memory, position + 4)[0] == 7:
                state = struct.unpack_from("<I", memory, position + 36)[0]
                if state:
                    def u32(offset):
                        return struct.unpack_from("<I", memory, position + offset)[0]

                    def u64(offset):
                        return struct.unpack_from("<Q", memory, position + offset)[0]

                    return {
                        "state": state,
                        "controller": u32(304),
                        "sector_size": u32(316),
                        "failure": u32(348),
                        "gpt_flags": u32(352),
                        "partition_blocks": u64(384),
                        "namespace_blocks": u64(464),
                    }
            position += 4


def monitor_command(path, command):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(5)
        connection.connect(path)
        greeting = b""
        while not greeting.endswith(b"(qemu) "):
            greeting += connection.recv(65536)
        connection.sendall((command + "\n").encode())
        response = b""
        while not response.endswith(b"(qemu) "):
            response += connection.recv(65536)
        if b"Error" in response or b"invalid" in response:
            raise RuntimeError(response.decode(errors="replace"))


def main():
    qemu, firmware, iso = sys.argv[1:4]
    with tempfile.TemporaryDirectory(prefix="australis-nvme-") as temporary:
        monitor = os.path.join(temporary, "monitor.sock")
        memory = os.path.join(temporary, "ram.bin")
        command = [
            qemu, "-machine", "q35", "-m", "256M",
            "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
            "-cdrom", iso,
            "-drive", f"if=none,id=nvme0,format=raw,readonly=on,file={iso}",
            "-device", "nvme,serial=australis,drive=nvme0",
            "-display", "none", "-serial", "none", "-net", "none", "-no-reboot",
            "-monitor", f"unix:{monitor},server,nowait",
        ]
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 60
            record = None
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f"QEMU exited with status {process.returncode}: {process.stderr.read().decode()}")
                if not os.path.exists(monitor):
                    time.sleep(0.2)
                    continue
                monitor_command(monitor, f'pmemsave 0 0x10000000 "{memory}"')
                record = boot_record(memory)
                if record and record["failure"]:
                    raise RuntimeError(f"kernel storage failed: {record}")
                if record and record["state"] == 262143:
                    if (record["controller"] != 2 or record["sector_size"] != 512 or
                            record["gpt_flags"] != 7 or record["partition_blocks"] == 0 or
                            record["namespace_blocks"] == 0):
                        raise RuntimeError(f"unexpected NVMe boot record: {record}")
                    print("Australis NVMe QEMU boot passed:", record)
                    return
                time.sleep(1)
            raise RuntimeError(f"NVMe boot timed out; last record: {record}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    main()
