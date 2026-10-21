#!/usr/bin/env python3
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "console"))
from serial_boot_smoke import PROMPT, capture_record, command, read_until


def verify_panic_qr_memory(record, memory_path):
    entry = record["panic_qr_entry"]
    scratch = record["panic_qr_scratch"]

    if entry == 0:
        raise AssertionError(
            "Hydrogen panic QR entry point is missing"
        )

    if scratch < 4096 or scratch % 4096 != 0:
        raise AssertionError(
            f"Invalid panic QR scratch address: {scratch:#x}"
        )

    if scratch + 4096 > os.path.getsize(memory_path):
        raise AssertionError(
            "Panic QR scratch page is outside captured RAM"
        )

    with open(memory_path, "rb") as memory:
        memory.seek(scratch)
        contents = memory.read(4096)

    if contents != bytes(4096):
        raise AssertionError(
            "Panic QR scratch page is not entirely zero"
        )

    return scratch


def verify_panic_stack(record, memory_path):
    base = record["panic_stack_base"]
    top = record["panic_stack_top"]
    scratch = record["panic_qr_scratch"]

    # Stack must occupy exactly four contiguous pages.
    if base < 4096 or base % 4096 != 0:
        raise AssertionError(
            f"Invalid panic stack base: {base:#x}"
        )

    if top != base + 16384:
        raise AssertionError(
            f"Invalid panic stack bounds: "
            f"{base:#x} - {top:#x}"
        )

    # The stack must not overlap our QR scratch page.
    if base < scratch + 4096 and scratch < top:
        raise AssertionError(
            "Panic stack overlaps QR scratch memory"
        )

    # The permanent stack must precede transient allocations.
    floor = record["transient_floor"]

    if floor == 0 or top > floor:
        raise AssertionError(
            "Panic stack is not below the transient region"
        )

    # Verify all 16 KiB are accessible in the RAM snapshot
    # and remain unused during normal execution.
    with open(memory_path, "rb") as memory:
        memory.seek(base)
        contents = memory.read(16384)

    if len(contents) != 16384:
        raise AssertionError(
            "Incomplete panic stack memory"
        )

    if any(contents):
        raise AssertionError(
            "Reserved panic stack contains unexpected data"
        )

    return base, top


def main():
    if len(sys.argv) != 5:
        raise SystemExit("usage: stage2_boot_smoke.py QEMU OVMF ISO ahci|nvme")
    qemu, ovmf, iso, transport = sys.argv[1:]
    if transport not in ("ahci", "nvme"):
        raise SystemExit("transport must be ahci or nvme")
    hello = (Path(__file__).resolve().parents[2] / "rootfs" / "hello.txt").read_bytes()
    with tempfile.TemporaryDirectory(prefix="australis-stage2-") as temporary:
        serial_path = os.path.join(temporary, "serial.sock")
        monitor_path = os.path.join(temporary, "monitor.sock")
        memory_path = os.path.join(temporary, "memory.bin")
        arguments = [qemu, "-machine", "q35", "-m", "256M", "-drive",
            f"if=pflash,format=raw,readonly=on,file={ovmf}", "-cdrom", iso,
            "-device", "qemu-xhci,id=xhci0", "-net", "none", "-display", "none",
            "-serial", f"unix:{serial_path},server=on,wait=off",
            "-monitor", f"unix:{monitor_path},server=on,wait=off"]
        if transport == "ahci":
            arguments += ["-device", "ich9-ahci,id=ahci0", "-drive",
                f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
                "-device", "ide-hd,drive=sata0,bus=ahci0.0"]
        else:
            arguments += ["-drive", f"if=none,id=nvme0,format=raw,readonly=on,file={iso}",
                "-device", "nvme,serial=australis,drive=nvme0"]
        process = subprocess.Popen(arguments, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 30
            while not os.path.exists(serial_path):
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode(errors="replace"))
                if time.monotonic() >= deadline:
                    raise TimeoutError("QEMU did not open serial socket")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(serial_path)
                read_until(connection, PROMPT, 60, process)
                before = capture_record(monitor_path, memory_path)
                stack_before = verify_panic_stack(
                    before, memory_path
                )
                scratch_before = verify_panic_qr_memory(before, memory_path)
                if (before["clock_state"] != 1 or before["ticks_per_millisecond"] == 0 or
                    before["stage2_state"] != 0 or before["dma_reservation_pages"] != 2112 or
                    before["xhci_mapping"] == 0 or before["xhci_mapping_size"] < 4096 or
                    before["dynamic_mapping_base"] == 0 or before["device_vector"] != 0 or
                    before["device_irqs"] != 0):
                    raise AssertionError(f"Stage 2 handoff is incomplete: {before}")
                for _ in range(16):
                    command(connection, process, b"cat /hello.txt", hello)
                command(connection, process, b"echo stage2 ready", b"stage2 ready\r\n")
                after = capture_record(monitor_path, memory_path)
                stack_after = verify_panic_stack(
                    after, memory_path
                )

                if stack_before != stack_after:
                    raise AssertionError(
                        "Panic stack reservation changed during execution"
                    )
                scratch_after = verify_panic_qr_memory(after, memory_path)
                if scratch_before != scratch_after:
                    raise AssertionError(
                        "Panic QR scratch page address changed"
                    )
                if before["panic_qr_entry"] != after["panic_qr_entry"]:
                        raise AssertionError(
                            "Hydrogen panic entry point changed"
                        )
                if (after["allocator_next"] != before["allocator_next"] or
                    after["free_page_count"] != before["free_page_count"] or
                    after["dynamic_mapping_base"] != before["dynamic_mapping_base"] or
                    after["xhci_mapping"] != before["xhci_mapping"] or
                    after["ring_dropped"] != 0 or after["event_dropped"] != 0 or
                    after["storage_cause"] != 0 or after["storage_state"] != 0):
                    raise AssertionError(f"Stage 2 stress changed owned resources: before={before}, after={after}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait(timeout=5)
    print(f"Australis {transport.upper()} Stage 2 QEMU services passed")


if __name__ == "__main__":
    main()
