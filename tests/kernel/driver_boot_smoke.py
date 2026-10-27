#!/usr/bin/env python3
"""Boot a real AUDR module, a corrupt module, and an absent module in QEMU."""

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


def run(*args, quiet=False):
    streams = {"stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL} if quiet else {}
    subprocess.run([str(arg) for arg in args], check=True, timeout=120, **streams)


def make_iso(repo, case_dir, bootloader, kernel, driver):
    rootfs = case_dir / "rootfs"
    shutil.copytree(repo / "rootfs", rootfs)
    (rootfs / "drivers.list").unlink(missing_ok=True)
    if driver is not None:
        (rootfs / "drivers.list").write_text("/Example.driver\n")
        (rootfs / "Example.driver").write_bytes(driver)
    hyfs = case_dir / "root.hyfs2.img"
    run("python3", repo / "tools/make_hyfs2_image.py", rootfs, hyfs)

    fat = case_dir / "efiboot.img"
    run("truncate", "-s", "8M", fat)
    run("mformat", "-i", fat, "::")
    run("mmd", "-i", fat, "::/EFI", "::/EFI/BOOT", "::/EFI/AUSTRALIS")
    run("mcopy", "-i", fat, bootloader, "::/EFI/BOOT/BOOTX64.EFI")
    run("mcopy", "-i", fat, kernel, "::/EFI/AUSTRALIS/KERNEL.BIN")
    iso_root = case_dir / "iso-root" / "EFI" / "BOOT"
    iso_root.mkdir(parents=True)
    shutil.copyfile(fat, iso_root / "efiboot.img")
    iso = case_dir / "test.iso"
    run("xorriso", "-as", "mkisofs", "-R", "-J", "-eltorito-alt-boot",
        "-e", "EFI/BOOT/efiboot.img", "-no-emul-boot", "-efi-boot-part",
        "--efi-boot-image", "-append_partition", "4",
        "9f5eb82e-692e-5a8f-b968-adaaa349dd93", hyfs,
        "-appended_part_as_gpt", "-o", iso, case_dir / "iso-root", quiet=True)
    return iso


def boot(qemu, ovmf, iso, serial_log):
    args = [str(qemu), "-machine", "q35,accel=tcg", "-m", "256M", "-drive",
            f"if=pflash,format=raw,readonly=on,file={ovmf}",
            "-device", "ich9-ahci,id=ahci0", "-drive",
            f"if=none,id=sata0,format=raw,snapshot=on,file={iso}",
            "-device", "ide-hd,drive=sata0,bus=ahci0.0", "-device",
            "qemu-xhci,id=xhci0", "-net", "none", "-display", "none",
            "-monitor", "none", "-serial", f"file:{serial_log}"]
    process = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            contents = serial_log.read_text(errors="replace") if serial_log.exists() else ""
            if "kmon> " in contents or "australis> " in contents:
                return contents
            if process.poll() is not None:
                raise AssertionError(f"QEMU exited {process.returncode}: {process.stderr.read()!r}")
            time.sleep(0.2)
        raise AssertionError(f"Australis did not reach a command prompt: {contents[-1000:]}")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("compiler", type=Path)
    parser.add_argument("repo", type=Path)
    parser.add_argument("qemu")
    parser.add_argument("ovmf", type=Path)
    parser.add_argument("packaged_iso", type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix="australis-audr-") as temporary:
        workspace = Path(temporary)
        bootloader = workspace / "BOOTX64.EFI"
        kernel = workspace / "KERNEL.BIN"
        driver = workspace / "Example.driver"
        run(compiler, "build", repo / "src/bootloader/australis.bootloader.hyproj",
            "-o", bootloader, "--hide-progress", "--hide-spinner", "--hide-log", quiet=True)
        run(compiler, "build", repo / "src/kernel/australis.kernel.hyproj",
            "-o", kernel, "--hide-progress", "--hide-spinner", "--hide-log", quiet=True)
        run(compiler, "build", repo / "src/drivers/usb/australis.drivers.usb.hyproj",
            "-o", driver, "--hide-progress", "--hide-spinner", "--hide-log", quiet=True)
        good = driver.read_bytes()
        assert (repo / "build/rootfs/drivers.list").read_text() == "/usb.driver\n"
        assert (repo / "build/rootfs/usb.driver").read_bytes() == good
        packaged_log = boot(args.qemu, args.ovmf, args.packaged_iso.resolve(),
                            workspace / "packaged-serial.log")
        assert "AUDR: driver loaded" in packaged_log, packaged_log[-1000:]
        print("AUDR packaged ISO: passed")
        bad = bytearray(good)
        bad[-1] ^= 1
        cases = (("valid", good, "AUDR: driver loaded"),
                 ("corrupt", bytes(bad), "AUDR: driver rejected (-5)"),
                 ("absent", None, None))
        for name, image, expected in cases:
            case_dir = workspace / name
            case_dir.mkdir()
            iso = make_iso(repo, case_dir, bootloader, kernel, image)
            log = boot(args.qemu, args.ovmf, iso, case_dir / "serial.log")
            if expected is None:
                assert "AUDR:" not in log, log[-1000:]
            else:
                assert expected in log, log[-1000:]
            print(f"AUDR {name}: passed")


if __name__ == "__main__":
    main()
