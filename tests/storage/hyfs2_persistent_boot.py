#!/usr/bin/env python3
"""Exercise AUEX writes, reboot recovery, and live removal on raw HyFS 2."""

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

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from serial_boot_smoke import PROMPT, monitor_command, read_until  # noqa: E402
from make_hyfs2_data_disk import create  # noqa: E402
from hyfs2 import Hyfs2Image, Hyfs2Error  # noqa: E402


def response(connection, process, timeout):
    deadline = time.monotonic() + timeout
    received = bytearray()
    while b"\n" + PROMPT not in received:
        if b"System halted." in received:
            raise AssertionError(f"kernel panic: {bytes(received[-5000:])!r}")
        if process.poll() is not None:
            raise RuntimeError(f"QEMU exited with status {process.returncode}")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"serial response timed out: {bytes(received[-5000:])!r}")
        connection.settimeout(min(remaining, 1))
        try:
            received.extend(connection.recv(4096))
        except socket.timeout:
            continue
    return bytes(received)


def run_once(qemu, firmware, iso, disk, transport, directory, expected, remove=False):
    serial = directory / "serial.sock"
    monitor = directory / "monitor.sock"
    command = [qemu, "-machine", "q35", "-m", "256M",
               "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
               "-cdrom", str(iso), "-display", "none", "-net", "none",
               "-no-reboot", "-serial", f"unix:{serial},server=on,wait=off",
               "-monitor", f"unix:{monitor},server=on,wait=off",
               "-drive", f"if=none,id=data0,format=raw,file={disk}"]
    if transport == "ahci":
        command += ["-device", "ich9-ahci,id=ahci0",
                    "-device", "ide-hd,id=data-device,drive=data0,bus=ahci0.0"]
        device_id = "data-device"
    else:
        command += ["-device", "nvme,id=data-device,serial=australis-data,drive=data0"]
        device_id = "data-device"
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL,
                               stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 15
        while not serial.exists():
            if process.poll() is not None:
                raise RuntimeError(process.stderr.read().decode(errors="replace"))
            if time.monotonic() > deadline:
                raise TimeoutError("QEMU did not open its serial socket")
            time.sleep(0.05)
        with socket.socket(socket.AF_UNIX) as connection:
            connection.connect(str(serial))
            read_until(connection, PROMPT, 90, process)
            connection.sendall(b"mounts\r")
            mounts = response(connection, process, 30)
            if b"/data: hyfs2 data0 read-write" not in mounts:
                raise AssertionError(f"data volume was not writable: {mounts!r}")
            if expected is not None:
                connection.sendall(b"run /stage6-file-test.exec\r")
                try:
                    result = response(connection, process, 60)
                except AssertionError as error:
                    memory = directory / "panic-memory.bin"
                    monitor_command(str(monitor), f'pmemsave 0 0x10000000 "{memory}"')
                    with memory.open("rb") as source:
                        ram = mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ)
                        record = 0
                        while True:
                            record = ram.find(b"AUBI", record)
                            if record < 0:
                                break
                            if struct.unpack_from("<I", ram, record + 4)[0] == 7:
                                entry = struct.unpack_from("<Q", ram, record + 1024)[0]
                                rip = struct.unpack_from("<Q", ram, record + 2616)[0]
                                rsp = struct.unpack_from("<Q", ram, record + 2640)[0]
                                stack = [hex(struct.unpack_from("<Q", ram, rsp + i * 8)[0])
                                         for i in range(16)]
                                allocation = [hex(struct.unpack_from("<Q", ram, record + offset)[0])
                                              for offset in (40, 48, 1152, 1184, 1192)]
                                raise AssertionError(
                                    f"{error}; boot_info={record:#x}, "
                                    f"entry={entry:#x}, rip={rip:#x}, "
                                    f"code={ram[rip:rip + 24].hex()}, "
                                    f"rsp={rsp:#x}, stack={stack}, allocation={allocation}") from error
                            record += 4
                    raise
                if expected not in result or b"User program exited cleanly." not in result:
                    raise AssertionError(f"persistent AUEX phase failed: {result!r}")
            if remove:
                monitor_command(str(monitor), f"device_del {device_id}")
                time.sleep(0.5)
                connection.sendall(b"version\r")
                answer = response(connection, process, 30)
                if b"version: 0.0.1" not in answer:
                    raise AssertionError(f"shell stopped after removal: {answer!r}")
                connection.sendall(b"cat /data/stage6-done\r")
                failed = response(connection, process, 30)
                if b"File read failed." not in failed:
                    raise AssertionError(f"removed volume remained readable: {failed!r}")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def inspect(disk, first, count, directory, expected_path=None, expected_data=None):
    volume = directory / "volume.hyfs2"
    with disk.open("rb") as image, volume.open("wb") as copy:
        image.seek(first * 512)
        copy.write(image.read(count * 512))
    filesystem = Hyfs2Image.open(volume)
    if expected_path is not None and filesystem.read_file(expected_path) != expected_data:
        raise AssertionError(f"recovered {expected_path} has unexpected contents")
    return filesystem


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    with tempfile.TemporaryDirectory(prefix="australis-hyfs2-persistent-") as temporary:
        directory = Path(temporary)
        disk = directory / "disk.img"
        first, count = create(Path(iso), disk)
        expected = (b"stage6-created", b"stage6-deleted",
                    b"stage6-deletion-recovered")
        for phase, marker in enumerate(expected):
            session = directory / f"boot-{phase + 1}"
            session.mkdir()
            run_once(qemu, firmware, iso, disk, transport, session, marker,
                     remove=phase == 2)
            checked = directory / f"check-{phase + 1}"
            checked.mkdir()
            if phase == 0:
                filesystem = inspect(disk, first, count, checked,
                                     "/Stage6/value", b"xy")
                if filesystem.stat("/Stage6/value").kind != 1:
                    raise AssertionError("created object is not a file")
            else:
                filesystem = inspect(disk, first, count, checked,
                                     "/stage6-done", b"yes")
                try:
                    filesystem.stat("/Stage6")
                except Hyfs2Error:
                    pass
                else:
                    raise AssertionError("deleted directory reappeared")
        # Damage the newest superblock on a copy. The older complete
        # generation must mount writable and repair the missing mirror.
        damaged = directory / "damaged.img"
        shutil.copyfile(disk, damaged)
        before = directory / "before-corruption"
        before.mkdir()
        latest = inspect(damaged, first, count, before)
        with damaged.open("r+b") as image:
            image.seek((first + latest.snapshot.slot) * 512)
            image.write(b"\0")
        fallback_dir = directory / "fallback"
        fallback_dir.mkdir()
        fallback = inspect(damaged, first, count, fallback_dir)
        if fallback.snapshot.generation >= latest.snapshot.generation:
            raise AssertionError("corrupt newest generation did not fall back")
        session = directory / "corrupt-reboot"
        session.mkdir()
        run_once(qemu, firmware, iso, damaged, transport, session, None)
        repaired_dir = directory / "repaired"
        repaired_dir.mkdir()
        repaired = inspect(damaged, first, count, repaired_dir)
        if repaired.snapshot.generation != fallback.snapshot.generation:
            raise AssertionError("corrupt fallback changed unexpectedly")
    print(f"HyFS 2 {transport.upper()} AUEX writes, reboot, and removal passed")


if __name__ == "__main__":
    main()
