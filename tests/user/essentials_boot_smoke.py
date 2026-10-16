#!/usr/bin/env python3
"""Exercise userland shell commands on a writable HyFS 2 data volume."""

from pathlib import Path
from tempfile import TemporaryDirectory
import socket
import subprocess
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from serial_boot_smoke import read_until  # noqa: E402
from make_hyfs2_data_disk import create  # noqa: E402

SHELL = b"australis> "


def run(connection, process, command, required):
    connection.sendall(command + b"\r")
    output = read_until(connection, SHELL, 45, process)
    if b"shell: program fault" in output or b"System failed" in output:
        raise AssertionError(f"{command!r} faulted: {output!r}")
    if (b"shell: exit status" in output and
            not any(b"shell: exit status" in marker for marker in required)):
        connection.sendall(b"exit\r")
        fallback = read_until(connection, b"kmon> ", 30, process)
        connection.sendall(b"trace\r")
        trace = read_until(connection, b"kmon> ", 30, process)
        raise AssertionError(f"{command!r} failed: {output!r}; "
                             f"fallback={fallback!r}; trace={trace!r}")
    for marker in required:
        if marker not in output:
            raise AssertionError(f"{command!r} missed {marker!r}: {output!r}")
    return output


def main():
    qemu, firmware, iso, transport = sys.argv[1:5]
    if transport not in ("ahci", "nvme"):
        raise ValueError("transport must be ahci or nvme")
    iso = str(Path(iso).resolve())
    with TemporaryDirectory(prefix="australis-essentials-") as temporary:
        directory = Path(temporary)
        disk = directory / "data.img"
        create(Path(iso), disk)
        serial = directory / "serial.sock"
        command = [qemu, "-machine", "q35", "-m", "256M", "-drive",
                   f"if=pflash,format=raw,readonly=on,file={firmware}",
                   "-cdrom", iso, "-display", "none", "-net", "none",
                   "-no-reboot", "-serial",
                   f"unix:{serial},server=on,wait=off", "-monitor", "none",
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
                    raise TimeoutError("QEMU did not open the serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(serial))
                opening = read_until(connection, SHELL, 90, process)
                if b"Australis command shell" not in opening:
                    raise AssertionError(f"normal shell did not start: {opening!r}")
                run(connection, process, b"pwd", [b"/\r\n"])
                run(connection, process, b"echo one 'two words'",
                    [b"one two words\r\n"])
                run(connection, process, b"cat /hello.txt",
                    [b"Hello from Australis HyFS."])
                run(connection, process, b"ls /", [b"hello.txt\r\n"])
                run(connection, process, b"tree /System", [b"Core/\r\n"])
                run(connection, process, b"run /System/Bin/version.exec", [b"Version: 0.0.1"])
                run(connection, process, b"sys-info", [b"Australis System Information"])
                run(connection, process, b"mem-info", [b"Australis Memory Information"])
                run(connection, process, b"ps", [b"PID STATE"])
                run(connection, process, b"drivers", [b"Active kernel drivers:"])
                run(connection, process, b"path", [b"PATH=/System/Bin"])
                connection.sendall(b"edit /System/Bin/version.exec\r")
                binary_editor = read_until(connection, b"^S Save", 45, process)
                if b"AUEX" not in binary_editor:
                    raise AssertionError(f"edit refused binary executable: {binary_editor!r}")
                connection.sendall(b"\x18")
                read_until(connection, SHELL, 30, process)
                connection.sendall(b"edit /hello.txt\r")
                read_until(connection, b"^S Save", 45, process)
                connection.sendall(b"!")
                read_until(connection, b"Ready  1:2", 30, process)
                connection.sendall(b"\x13")
                read_only = read_until(connection, b"Read-only volume", 30, process)
                if b"Read-only volume" not in read_only:
                    raise AssertionError(f"read-only save was unclear: {read_only!r}")
                connection.sendall(b"\x0f/data/hello-copy.txt\r")
                read_until(connection, b"Saved", 30, process)
                connection.sendall(b"\x18")
                read_until(connection, SHELL, 30, process)
                run(connection, process, b"cat /data/hello-copy.txt",
                    [b"!Hello from Australis HyFS."])
                run(connection, process, b"rm /data/hello-copy.txt", [])
                changed = run(connection, process, b"cd /data", [])
                if b"cd:" in changed:
                    connection.sendall(b"exit\r")
                    read_until(connection, b"kmon> ", 30, process)
                    connection.sendall(b"mounts\r")
                    mounts = read_until(connection, b"kmon> ", 30, process)
                    raise AssertionError(
                        f"data directory unavailable: {changed!r}; mounts={mounts!r}")
                run(connection, process, b"pwd", [b"/data\r\n"])
                run(connection, process, b"cd ..", [])
                run(connection, process, b"pwd", [b"/\r\n"])
                run(connection, process, b"cd /data", [])
                run(connection, process,
                    b"cp /System/Bin/version.exec version.exec", [])
                run(connection, process, b"path /data", [b"PATH=/data"])
                run(connection, process, b"version", [b"Version: 0.0.1"])
                run(connection, process, b"cat /hello.txt",
                    [b"shell: command not found"])
                run(connection, process, b"path /System/Bin:/data",
                    [b"PATH=/System/Bin:/data"])
                run(connection, process, b"cat /hello.txt",
                    [b"Hello from Australis HyFS."])
                run(connection, process, b"rm version.exec", [])
                connection.sendall(b"edit note.txt\r")
                editor = read_until(connection, b"^S Save", 45, process)
                if b"AUSTRALIS EDIT" not in editor:
                    raise AssertionError(f"text editor did not open: {editor!r}")
                connection.sendall(b"hello editor")
                read_until(connection, b"Ready  1:13", 30, process)
                connection.sendall(b"\x13")
                saved = read_until(connection, b"Saved", 30, process)
                if b"Saved" not in saved:
                    raise AssertionError(f"text editor save failed: {saved!r}")
                connection.sendall(b"\x18")
                read_until(connection, SHELL, 30, process)
                run(connection, process, b"cat note.txt", [b"hello editor"])
                connection.sendall(b"hexedit note.txt\r")
                hex_editor = read_until(connection, b"^S Save", 45, process)
                if b"68 65 6C 6C 6F" not in hex_editor:
                    raise AssertionError(f"hex editor did not show bytes: {hex_editor!r}")
                connection.sendall(b"48")
                read_until(connection, b"Ready  offset 1", 30, process)
                connection.sendall(b"\x13")
                hex_saved = read_until(connection, b"Saved", 30, process)
                if b"Saved" not in hex_saved:
                    raise AssertionError(f"hex editor save failed: {hex_saved!r}")
                connection.sendall(b"\x0f")
                read_until(connection, b"Save as: ", 30, process)
                connection.sendall(b"/data/hexcopy.txt\r")
                read_until(connection, b"Saved", 30, process)
                connection.sendall(b"\x18")
                read_until(connection, SHELL, 30, process)
                run(connection, process, b"cat note.txt", [b"Hello editor"])
                run(connection, process, b"cat hexcopy.txt", [b"Hello editor"])
                run(connection, process, b"rm hexcopy.txt", [])
                connection.sendall(b"edit note.txt\r")
                read_until(connection, b"^S Save", 45, process)
                connection.sendall(b"\x1b[F\x1b[D!\x13")
                read_until(connection, b"Saved", 30, process)
                connection.sendall(b"\x18")
                read_until(connection, SHELL, 30, process)
                run(connection, process, b"cat note.txt", [b"Hello edito!r"])
                run(connection, process, b"rm note.txt", [])
                run(connection, process, b"mkdir demo", [])
                run(connection, process, b"touch demo/empty", [])
                run(connection, process, b"touch demo/empty", [])
                run(connection, process, b"cp /hello.txt demo/copy", [])
                run(connection, process, b"cat demo/copy",
                    [b"Hello from Australis HyFS."])
                run(connection, process, b"cp /readme.txt demo/readme", [])
                run(connection, process, b"cat demo/readme",
                    [b"Australis boots a separate freestanding kernel image",
                     b"can use the mounted VFS to open files"])
                run(connection, process, b"mv demo/copy demo/moved", [])
                run(connection, process, b"tree demo",
                    [b"empty\r\n", b"moved\r\n", b"readme\r\n"])
                run(connection, process, b"rm demo/moved", [])
                run(connection, process, b"rm demo/readme", [])
                run(connection, process, b"rm demo/empty", [])
                run(connection, process, b"rm demo", [])
                run(connection, process, b"ls /data", [SHELL])
                run(connection, process, b"history", [b"rm demo\r\n"])
                run(connection, process, b"clear", [b"\x1b[2J\x1b[H"])
                run(connection, process, b"unknown-command",
                    [b"shell: command not found"])
                run(connection, process, b"cat /missing",
                    [b"shell: exit status 4"])
                # Exercise the bounded process-history ring beyond its 64 slots.
                for repeated in range(70):
                    try:
                        run(connection, process, b"version", [b"Version: 0.0.1"])
                    except AssertionError as error:
                        raise AssertionError(
                            f"repeated launch {repeated + 1} failed: {error}") from error
                connection.sendall(b"exit\r")
                fallback = read_until(connection, b"kmon> ", 30, process)
                if b"System session ended; entering KMon." not in fallback:
                    raise AssertionError(f"shell exit missed KMon: {fallback!r}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f"Australis {transport.upper()} essentials shell commands passed")


if __name__ == "__main__":
    main()
