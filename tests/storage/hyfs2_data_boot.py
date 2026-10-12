#!/usr/bin/env python3
"""Verify a disposable HyFS 2 data disk across live controller boots."""

from pathlib import Path
import mmap
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from make_hyfs2_data_disk import DATA_BLOCKS, PROBE_MAGIC, create  # noqa: E402


def monitor_command(path, command):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(10)
        connection.connect(path)
        response = b""
        while not response.endswith(b"(qemu) "):
            response += connection.recv(65536)
        connection.sendall((command + "\n").encode())
        response = b""
        while not response.endswith(b"(qemu) "):
            response += connection.recv(65536)
        if b"Error" in response or b"invalid" in response:
            raise RuntimeError(response.decode(errors="replace"))


def boot_record(path):
    with open(path, "rb") as image:
        memory = mmap.mmap(image.fileno(), 0, access=mmap.ACCESS_READ)
        location = 0
        while True:
            location = memory.find(b"AUBI", location)
            if location < 0:
                return None
            if struct.unpack_from("<I", memory, location + 4)[0] == 7:
                u32 = lambda offset: struct.unpack_from("<I", memory, location + offset)[0]
                u64 = lambda offset: struct.unpack_from("<Q", memory, location + offset)[0]
                if u32(36):
                    return {"state": u32(36), "exception": u32(188),
                            "controller": u32(304), "data_mounted": u32(2688),
                            "data_mount_status": u32(2692),
                            "data_lba": u64(2696), "data_blocks": u64(2704),
                            "probe": u32(2712)}
            location += 4


def boot(qemu, firmware, iso, disk, transport, temporary, fault=None,
         require_probe=True):
    monitor = str(temporary / "monitor.sock")
    memory = str(temporary / "ram.bin")
    command = [qemu, "-machine", "q35", "-m", "256M",
               "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
               "-cdrom", str(iso), "-display", "none", "-serial", "none",
               "-net", "none", "-no-reboot", "-monitor", f"unix:{monitor},server,nowait"]
    drive_file = str(disk)
    if fault is not None:
        drive_file = f"blkdebug:{fault}:{disk}"
    drive = f"if=none,id=data0,format=raw,file={drive_file}"
    if transport == "ahci":
        command += ["-device", "ich9-ahci,id=ahci0", "-drive", drive,
                    "-device", "ide-hd,drive=data0,bus=ahci0.0"]
    else:
        command += ["-drive", drive, "-device", "nvme,id=nvme0,serial=australis-data",
                    "-device", "nvme-ns,drive=data0,nsid=1,write-cache=on"]
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 90
        last = None
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError(f"QEMU exited: {process.stderr.read().decode(errors='replace')}")
            if not os.path.exists(monitor):
                time.sleep(0.2)
                continue
            monitor_command(monitor, f'pmemsave 0 0x10000000 "{memory}"')
            last = boot_record(memory)
            if last and last["exception"]:
                raise RuntimeError(f"kernel exception: {last}")
            if last and last["state"] == 262143 and (
                    last["probe"] or (not require_probe and last["data_mounted"])):
                return last
            time.sleep(1)
        raise RuntimeError(f"{transport} data boot timed out: {last}")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def data_bytes(path, first, block, count):
    with path.open("rb") as image:
        image.seek((first + block) * 512)
        return image.read(count * 512)


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    with tempfile.TemporaryDirectory(prefix="australis-hyfs2-data-") as directory:
        temporary = Path(directory)
        disk = temporary / "data.img"
        first, count = create(Path(iso), disk, probe=True)
        assert count == DATA_BLOCKS
        assert data_bytes(disk, first, 3, 1).startswith(PROBE_MAGIC)
        ordinary = temporary / "ordinary-data.img"
        ordinary_first, ordinary_count = create(Path(iso), ordinary)
        if (ordinary_first, ordinary_count) != (first, count):
            raise AssertionError("ordinary data disk geometry differs from probe fixture")
        session = temporary / "ordinary"
        session.mkdir()
        record = boot(qemu, firmware, iso, ordinary, transport, session,
                      require_probe=False)
        if record["data_mounted"] != 1 or record["probe"] != 0:
            raise AssertionError(f"ordinary data volume did not mount cleanly: {record}")
        with disk.open("rb") as image:
            image.seek(first * 512)
            original_superblock = image.read(512)
            image.seek((first + 2) * 512)
            original_table = image.read(512)
        expected = bytes((i * 29 + 7) % 256 for i in range(9 * 512))
        for attempt, result in enumerate((1, 2), start=1):
            session = temporary / f"boot-{attempt}"
            session.mkdir()
            record = boot(qemu, firmware, iso, disk, transport, session)
            if (record["controller"] != (1 if transport == "ahci" else 2) or
                    record["data_mounted"] != 1 or record["data_mount_status"] != 0 or
                    record["data_lba"] != first or record["data_blocks"] != count or
                    record["probe"] != result):
                raise AssertionError(f"unexpected live probe result: {record}")
            if data_bytes(disk, first, 4, 9) != expected:
                raise AssertionError("write/flush did not persist all nine sectors")
            with disk.open("rb") as image:
                image.seek(first * 512)
                if image.read(512) != original_superblock:
                    raise AssertionError("probe modified the active superblock")
                image.seek((first + 1) * 512)
                if image.read(512) != original_superblock:
                    raise AssertionError("writable mount did not mirror the initial superblock")
                image.seek((first + 2) * 512)
                if image.read(512) != original_table:
                    raise AssertionError("probe modified the object table")
        failure_disk = temporary / "write-failure.img"
        shutil.copyfile(disk, failure_disk)
        with failure_disk.open("r+b") as image:
            image.seek((first + 4) * 512)
            image.write(bytes(9 * 512))
        config = temporary / "write-error.conf"
        config.write_text(f'[inject-error]\nevent = "write_aio"\niotype = "write"\nsector = "{first + 4}"\nerrno = "5"\n')
        session = temporary / "write-failure"
        session.mkdir()
        record = boot(qemu, firmware, iso, failure_disk, transport, session, config)
        if record["data_mounted"] != 1 or record["probe"] != 4:
            observed = data_bytes(failure_disk, first, 4, 9)
            first_changed = next((i for i, byte in enumerate(observed) if byte), -1)
            raise AssertionError(f"injected write failure was not reported: {record}; first changed byte={first_changed}")
        if data_bytes(failure_disk, first, 4, 9) != bytes(9 * 512):
            raise AssertionError("injected write failure changed the fixture")
        # Reboot the same disk without fault injection. The failed command
        # must leave the reserved test area reusable, and a later successful
        # write/flush must still survive one more reboot.
        for attempt, result in enumerate((1, 2), start=1):
            session = temporary / f"after-write-failure-{attempt}"
            session.mkdir()
            record = boot(qemu, firmware, iso, failure_disk, transport, session)
            if record["data_mounted"] != 1 or record["probe"] != result:
                raise AssertionError(f"failed-write reboot result: {record}")
            if data_bytes(failure_disk, first, 4, 9) != expected:
                raise AssertionError("recovered write/flush did not persist")
        # QEMU's AHCI path forwards the injected backend flush error. Its NVMe
        # emulation completes Flush without forwarding either blkdebug flush
        # event, so NVMe flush rejection remains covered by the host mock.
        if transport == "ahci":
            flush_disk = temporary / "flush-failure.img"
            shutil.copyfile(disk, flush_disk)
            with flush_disk.open("r+b") as image:
                image.seek((first + 4) * 512)
                image.write(bytes(9 * 512))
            flush_config = temporary / "flush-error.conf"
            flush_config.write_text('[inject-error]\nevent = "flush_to_os"\niotype = "flush"\nerrno = "5"\n'
                                    '[inject-error]\nevent = "flush_to_disk"\niotype = "flush"\nerrno = "5"\n')
            session = temporary / "flush-failure"
            session.mkdir()
            record = boot(qemu, firmware, iso, flush_disk, transport, session, flush_config)
            if record["data_mounted"] != 1 or record["probe"] != 5:
                raise AssertionError(f"injected flush failure was not reported: {record}")
            with flush_disk.open("r+b") as image:
                image.seek((first + 4) * 512)
                image.write(bytes(9 * 512))
            for attempt, result in enumerate((1, 2), start=1):
                session = temporary / f"after-flush-failure-{attempt}"
                session.mkdir()
                record = boot(qemu, firmware, iso, flush_disk, transport, session)
                if record["data_mounted"] != 1 or record["probe"] != result:
                    raise AssertionError(f"failed-flush reboot result: {record}")
                if data_bytes(flush_disk, first, 4, 9) != expected:
                    raise AssertionError("recovered flush did not persist")
        print(f"HyFS 2 {transport.upper()} data write, flush, reboot, and injected failure recovery passed")


if __name__ == "__main__":
    main()
