#!/usr/bin/env python3
"""Exercise child context, launch errors, EOF, and cleanup in the live shell."""

from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "usb"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from serial_boot_smoke import capture_record, capture_screen, read_until, screen_lines  # noqa: E402
from xhci_keyboard_smoke import send_text  # noqa: E402
from make_hyfs2_data_disk import create  # noqa: E402
from hyfs2 import Hyfs2Image  # noqa: E402
from system_image_recovery_smoke import boot_partition  # noqa: E402

SHELL = b"australis> "


def run(connection, process, command, marker=None):
    connection.sendall(command + b"\r")
    output = read_until(connection, SHELL, 45, process)
    if marker is not None and marker not in output:
        raise AssertionError(f"{command!r} missed {marker!r}: {output!r}")
    if b"shell: program fault" in output or b"System failed" in output:
        raise AssertionError(f"{command!r} faulted: {output!r}")
    return output


def prepare(source, fixture, image, volume):
    shutil.copyfile(source, image)
    first, last = boot_partition(image, volume)
    filesystem = Hyfs2Image.open(volume)
    filesystem.put("/System/Bin/context-probe.exec", fixture.read_bytes())
    data = volume.read_bytes()
    if len(data) != (last - first + 1) * 512:
        raise AssertionError("fixture changed boot partition size")
    with image.open("r+b") as target:
        target.seek(first * 512)
        target.write(data)


def main():
    qemu, firmware, source, fixture, transport = sys.argv[1:6]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    with tempfile.TemporaryDirectory(prefix="australis-stage2-") as temporary:
        directory = Path(temporary)
        image = directory / "stage2.iso"
        prepare(Path(source), Path(fixture), image, directory / "volume.img")
        disk = directory / "data.img"
        create(image, disk)
        serial = directory / "serial.sock"
        monitor = directory / "monitor.sock"
        command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
                   f"if=pflash,format=raw,readonly=on,file={firmware}",
                   "-cdrom", str(image), "-display", "none", "-net", "none",
                   "-no-reboot", "-serial", f"unix:{serial},server=on,wait=off",
                   "-monitor", f"unix:{monitor},server=on,wait=off",
                   "-device", "qemu-xhci,id=xhci0", "-device",
                   "usb-kbd,id=kbd0,bus=xhci0.0",
                   "-drive", f"if=none,id=data0,format=raw,file={disk}"]
        if transport == "ahci":
            command += ["-device", "ich9-ahci,id=ahci0",
                        "-device", "ide-hd,drive=data0,bus=ahci0.0"]
        else:
            command += ["-device", "nvme,id=data-device,serial=australis-data",
                        "-device", "nvme-ns,drive=data0,nsid=1,write-cache=on"]
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 45
            while not serial.exists():
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(serial))
                opening = read_until(connection, SHELL, 90, process)
                if b"Australis command shell" not in opening:
                    raise AssertionError(f"shell failed to start: {opening!r}")
                run(connection, process, b"cat /hello.txt", b"Hello from Australis HyFS.")
                run(connection, process, b"ls /", b"hello.txt\r\n")
                run(connection, process, b"version", b"Version: 0.0.1")
                for command_text, marker in (("cat /hello.txt\n", b"Hello from Australis HyFS."),
                                             ("ls /\n", b"hello.txt\r\n"),
                                             ("version\n", b"Version: 0.0.1")):
                    send_text(str(monitor), command_text)
                    usb_output = read_until(connection, SHELL, 30, process)
                    if marker not in usb_output:
                        raise AssertionError(f"USB command output differed: {usb_output!r}")
                    screen = capture_screen(str(monitor), str(directory / "screen.ppm"))
                    text = marker.decode(errors="replace").strip()
                    if not any(text in line for line in screen_lines(screen)):
                        raise AssertionError(f"framebuffer missed USB output {text!r}")
                run(connection, process, b"set NOTE local")
                local = run(connection, process, b"context-probe", b"cwd=/")
                if b"env=NOTE=" in local:
                    raise AssertionError("unexported variable reached child")
                run(connection, process, b"export NOTE")
                exported = run(connection, process, b"context-probe", b"env=NOTE=local")
                if b"env=PATH=/System/Bin" not in exported:
                    raise AssertionError("PATH did not reach child")
                run(connection, process, b"set NOTE changed")
                run(connection, process, b"context-probe", b"env=NOTE=changed")
                run(connection, process, b"unset NOTE")
                removed = run(connection, process, b"context-probe", b"cwd=/")
                if b"env=NOTE=" in removed:
                    raise AssertionError("unset variable reached child")
                run(connection, process, b"cd /data")
                run(connection, process, b"context-probe", b"cwd=/data")
                run(connection, process, b"run /missing.exec",
                    b"shell: executable not found")
                run(connection, process, b"run /System/Bin",
                    b"shell: execution denied")
                run(connection, process, b"touch bad.exec")
                run(connection, process, b"run /data/bad.exec",
                    b"shell: invalid executable image")
                run(connection, process, b"rm bad.exec")
                first = capture_record(str(monitor), str(directory / "first.bin"))
                for _ in range(4):
                    run(connection, process, b"context-probe", b"cwd=/data")
                    run(connection, process, b"run /missing.exec",
                        b"shell: executable not found")
                second = capture_record(str(monitor), str(directory / "second.bin"))
                for field in ("user_descriptors", "free_page_count",
                              "allocator_next", "heap_next", "heap_end",
                              "dynamic_mapping_base",
                              "memory_error", "mapping_error", "event_dropped",
                              "ring_dropped"):
                    if second[field] != first[field]:
                        raise AssertionError(f"resource counter {field} changed: "
                                             f"{first[field]} -> {second[field]}; "
                                             f"heap next {first['heap_next']} -> "
                                             f"{second['heap_next']}, heap end "
                                             f"{first['heap_end']} -> "
                                             f"{second['heap_end']}")
                if second["user_descriptors"] != 0:
                    raise AssertionError("child descriptors remain open")
                connection.sendall(b"\x04")
                ending = read_until(connection, b"kmon> ", 30, process)
                if b"System session ended; entering KMon." not in ending:
                    raise AssertionError(f"terminal EOF did not leave shell: {ending!r}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} Stage 2 shell context passed")


if __name__ == "__main__":
    main()
