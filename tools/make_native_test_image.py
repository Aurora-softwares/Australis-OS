#!/usr/bin/env python3
"""Assemble a tiny AUN1 image for the native shell regression."""

from pathlib import Path
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory


def main() -> None:
    source, output = map(Path, sys.argv[1:3])
    with TemporaryDirectory(prefix="australis-native-image-") as directory:
        work = Path(directory)
        obj, elf, binary = (work / name for name in
                            ("program.o", "program.elf", "program.bin"))
        subprocess.run(["gcc", "-c", "-nostdlib", "-o", str(obj), str(source)],
                       check=True)
        subprocess.run(["ld", "-nostdlib", "-Ttext=0", "-e", "_start",
                        "-o", str(elf), str(obj)], check=True)
        relocations = subprocess.check_output(
            ["readelf", "-r", str(elf)], text=True)
        if "There are no relocations" not in relocations:
            raise RuntimeError("native test image contains unresolved relocations")
        subprocess.run(["objcopy", "-O", "binary", "--only-section=.text",
                        str(elf), str(binary)], check=True)
        code = binary.read_bytes()
    if not 0 < len(code) <= 4096:
        raise RuntimeError("native test image must fit in one code page")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(struct.pack("<4sHBB", b"AUN1", len(code), 0, 0) + code)


if __name__ == "__main__":
    main()
