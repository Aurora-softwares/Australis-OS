#!/usr/bin/env python3
"""Boot the raw kernel with QEMU AHCI or NVMe and verify its HyFS root."""

import mmap
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import time
import uuid
import zlib


HYFS_TYPE_GUID = uuid.UUID("9f5eb82e-692e-5a8f-b968-adaaa349dd93").bytes_le


def hyfs_partition(path):
    with open(path, "rb") as image:
        image.seek(512)
        header = image.read(512)
        if header[:8] != b"EFI PART":
            raise RuntimeError("boot image has no GPT")
        entries_lba = struct.unpack_from("<Q", header, 72)[0]
        entry_count, entry_size = struct.unpack_from("<II", header, 80)
        for index in range(entry_count):
            image.seek(entries_lba * 512 + index * entry_size)
            entry = image.read(entry_size)
            if entry[:16] == HYFS_TYPE_GUID:
                first, last = struct.unpack_from("<QQ", entry, 32)
                return first, last - first + 1
    raise RuntimeError("boot image has no HyFS GPT partition")


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
                        "exception": u32(188),
                        "gpt_flags": u32(352),
                        "partition_blocks": u64(384),
                        "namespace_blocks": u64(464),
                        "hydrogen_entry": u32(472),
                        "hydrogen_status": u32(476),
                        "hydrogen_page": u64(480),
                        "hydrogen_heap_result": u32(488),
                        "hydrogen_string_length": u32(492),
                        "hydrogen_nvme_read": u32(496),
                        "hydrogen_gpt_open": u32(500),
                        "hydrogen_gpt_status": u32(504),
                        "hydrogen_block_status": u32(508),
                        "raw_entry": u64(1024),
                        "raw_code_size": u64(1032),
                        "raw_stack_base": u64(1048),
                        "raw_stack_top": u64(1056),
                        "root_state": u32(1072),
                        "root_mount_status": u32(1076),
                        "root_file_length": u64(1080),
                        "root_file_crc": u64(1088),
                        "root_first_lba": u64(1096),
                        "root_block_count": u64(1104),
                        "root_read_status": u32(1112),
                        "root_readme_length": u64(1120),
                        "root_readme_crc": u64(1128),
                        "root_readme_status": u32(1136),
                        "mapping_self_test": u32(1200),
                        "hydrogen_page_value": struct.unpack_from("<Q", memory, u64(480) + 8)[0]
                        if u64(480) + 16 <= len(memory) else 0,
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
    transport = sys.argv[4] if len(sys.argv) > 4 else "nvme"
    if transport not in ("nvme", "ahci"):
        raise ValueError("transport must be nvme or ahci")
    root_first_lba, root_block_count = hyfs_partition(iso)
    hello = (Path(__file__).resolve().parents[2] / "rootfs" / "hello.txt").read_bytes()
    readme = (Path(__file__).resolve().parents[2] / "rootfs" / "readme.txt").read_bytes()
    if len(readme) <= 512:
        raise RuntimeError("live HyFS fixture must cross a sector boundary")
    with tempfile.TemporaryDirectory(prefix="australis-boot-") as temporary:
        monitor = os.path.join(temporary, "monitor.sock")
        memory = os.path.join(temporary, "ram.bin")
        command = [
            qemu, "-machine", "q35", "-m", "256M",
            "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
            "-cdrom", iso,
            "-display", "none", "-serial", "none", "-net", "none", "-no-reboot",
            "-monitor", f"unix:{monitor},server,nowait",
        ]
        if transport == "nvme":
            command.extend(["-drive", f"if=none,id=nvme0,format=raw,readonly=on,file={iso}",
                            "-device", "nvme,serial=australis,drive=nvme0"])
        else:
            command.extend(["-device", "ich9-ahci,id=ahci0",
                            "-drive", f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
                            "-device", "ide-hd,drive=sata0,bus=ahci0.0"])
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
                if record and record["exception"]:
                    raise RuntimeError(f"kernel exception: {record}")
                if record and record["hydrogen_status"]:
                    raise RuntimeError(f"kernel entry failed: {record}")
                if record and record["state"] == 262143:
                    expected_controller = 2 if transport == "nvme" else 1
                    if (record["controller"] != expected_controller or record["sector_size"] != 512 or
                            record["gpt_flags"] != 7 or record["partition_blocks"] == 0 or
                            (transport == "nvme" and record["namespace_blocks"] == 0) or
                            record["hydrogen_entry"] != 1 or record["hydrogen_status"] != 0 or
                            record["mapping_self_test"] != 0 or
                            record["hydrogen_page"] < 4096 or record["hydrogen_page_value"] != 123456789 or
                            record["hydrogen_heap_result"] != 99 or record["hydrogen_string_length"] != 9 or
                            record["hydrogen_gpt_open"] != 1 or record["hydrogen_gpt_status"] != 0 or
                            record["hydrogen_block_status"] != 0 or
                            record["root_state"] != 7 or record["root_mount_status"] != 0 or
                            record["root_read_status"] != 0 or
                            record["root_file_length"] != len(hello) or
                            record["root_file_crc"] != zlib.crc32(hello) or
                            record["root_readme_status"] != 0 or
                            record["root_readme_length"] != len(readme) or
                            record["root_readme_crc"] != zlib.crc32(readme) or
                            record["root_first_lba"] != root_first_lba or
                            record["root_block_count"] != root_block_count or
                            (transport == "nvme" and record["hydrogen_nvme_read"] != 1) or
                            record["raw_entry"] < 4096 or record["raw_code_size"] < 1 or
                            record["raw_stack_top"] - record["raw_stack_base"] != 65536):
                        raise RuntimeError(f"unexpected {transport.upper()} boot record: {record}")
                    print(f"Australis {transport.upper()} QEMU boot passed:", record)
                    return
                time.sleep(1)
            raise RuntimeError(f"{transport.upper()} boot timed out; last record: {record}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    main()
