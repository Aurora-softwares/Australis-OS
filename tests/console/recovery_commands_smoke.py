#!/usr/bin/env python3
"""Exercise KMon recovery commands against the source-built ISO in QEMU."""

from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from serial_boot_smoke import monitor_command, read_until  # noqa: E402


def exercise(qemu: str, firmware: str, iso: str, action: str) -> None:
    with tempfile.TemporaryDirectory(prefix=f"australis-kmon-{action}-") as temporary:
        serial_path = str(Path(temporary) / "serial.sock")
        monitor_path = str(Path(temporary) / "monitor.sock")
        command = [
            qemu, "-machine", "q35", "-m", "256M",
            "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
            "-device", "ich9-ahci,id=ahci0",
            "-drive", f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
            "-device", "ide-hd,drive=sata0,bus=ahci0.0",
            "-display", "none", "-net", "none",
            "-serial", f"unix:{serial_path},server=on,wait=off",
            "-monitor", f"unix:{monitor_path},server=on,wait=off",
        ]
        if action != "continue":
            command.append("-no-reboot")
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 15
            while not Path(serial_path).exists() or not Path(monitor_path).exists():
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open its sockets")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as serial:
                serial.connect(serial_path)
                serial.settimeout(0.2)
                selected = action == "continue"
                debug = action == "panic"
                prompt = b"rescue> " if selected else b"kmon> "
                selected_marker = b"[BOOT] Rescue mode selected." if selected else b"[BOOT] Debug mode selected."
                last_key = 0.0
                opening = bytearray()
                deadline = time.monotonic() + 50
                while prompt not in opening:
                    if process.poll() is not None:
                        raise RuntimeError("QEMU exited before KMon prompt")
                    if time.monotonic() >= deadline:
                        raise AssertionError(f"KMon prompt missing for {action}: {opening[-500:]!r}")
                    if (selected or debug) and selected_marker not in opening and \
                            time.monotonic() - last_key >= 1.0:
                        monitor_command(monitor_path, "sendkey r 70" if selected else "sendkey d 70")
                        last_key = time.monotonic()
                    try:
                        opening.extend(serial.recv(4096))
                    except socket.timeout:
                        pass

                if selected or debug:
                    time.sleep(0.3)  # allow the injected key release before a possible reset
                if selected:
                    serial.sendall(b"mounts\r")
                    empty_mounts = read_until(serial, b"rescue> ", 15, process)
                    if (b"No filesystems mounted.\r\n" not in empty_mounts or
                            b"/: hyfs boot0\r\n" in empty_mounts):
                        raise AssertionError(
                            f"early Rescue reported an unavailable root: {empty_mounts!r}")
                    serial.sendall(b"devices\r")
                    devices = read_until(serial, b"rescue> ", 15, process)
                    if b"boot0: storage not initialized\r\n" not in devices:
                        raise AssertionError(f"Rescue reported storage ready: {devices!r}")
                    serial.sendall(b"pages\r")
                    pages = read_until(serial, b"rescue> ", 15, process)
                    if b"Physical pages (4 KiB):\r\n" not in pages:
                        raise AssertionError(f"Rescue cannot inspect allocator: {pages!r}")
                    serial.sendall(b"memmap\r")
                    memory_map = read_until(serial, b"rescue> ", 15, process)
                    if b"EFI memory map:\r\n" not in memory_map:
                        raise AssertionError(f"Rescue cannot inspect memory map: {memory_map!r}")
                    for name in (b"devices", b"mounts", b"memmap", b"pages"):
                        serial.sendall(name + b" extra\r")
                        usage = read_until(serial, b"rescue> ", 15, process)
                        if b"Usage: " + name + b"\r\n" not in usage:
                            raise AssertionError(f"KMon accepted an extra {name!r} argument: {usage!r}")
                if debug:
                    serial.sendall(b"memmap\r")
                    memory_map = read_until(serial, b"kmon> ", 15, process)
                    if b"type physical-start pages:\r\n" not in memory_map:
                        raise AssertionError(f"Debug memory ranges unavailable: {memory_map!r}")
                serial.sendall(action.encode() + b"\r")
                if action == "continue":
                    result = read_until(serial, b"kmon> ", 60, process)
                    if b"Restarting into normal boot.\r\n" not in result:
                        raise AssertionError(f"Rescue did not resume normal boot: {result[-800:]!r}")
                    serial.sendall(b"mounts\r")
                    mounted = read_until(serial, b"kmon> ", 15, process)
                    if b"/: hyfs boot0\r\n" not in mounted:
                        raise AssertionError(f"normal boot did not mount root: {mounted!r}")
                elif action == "reboot":
                    result = read_until(serial, b"Rebooting system.\r\n", 15, process)
                    if b"Rebooting system." not in result:
                        raise AssertionError(result)
                    try:
                        process.wait(timeout=15)
                    except subprocess.TimeoutExpired as error:
                        raise AssertionError("reboot did not reset QEMU") from error
                    if process.returncode != 0:
                        raise AssertionError(f"QEMU reset exit status {process.returncode}")
                elif action == "halt":
                    read_until(serial, b"System halted.\r\n", 15, process)
                    serial.sendall(b"help\r")
                    serial.settimeout(1)
                    try:
                        after = serial.recv(4096)
                    except socket.timeout:
                        after = b""
                    if b"kmon> " in after or b"Commands: help" in after or process.poll() is not None:
                        raise AssertionError("halt returned to the command loop")
                else:
                    report = read_until(serial,
                        b"System halted. Power cycle or reset to continue.\r\n", 20, process)
                    if b"Triggering deliberate kernel page fault.\r\n" not in report or \
                            b"*** AUSTRALIS KERNEL PANIC ***\r\n" not in report:
                        raise AssertionError(f"debug panic did not reach fatal handler: {report[-1200:]!r}")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            if process.stderr is not None:
                process.stderr.close()


def main() -> None:
    qemu, firmware, iso = sys.argv[1:4]
    for action in ("continue", "reboot", "halt", "panic"):
        exercise(qemu, firmware, iso, action)
        print(f"Australis KMon {action} QEMU test passed")


if __name__ == "__main__":
    main()
