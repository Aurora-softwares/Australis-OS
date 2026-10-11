#!/usr/bin/env python3
"""Pin a generated HyFS v1 image for future reader compatibility checks."""

import argparse
import hashlib
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import zlib


REPOSITORY = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(REPOSITORY / "tools"))
from make_hyfs_image import pack  # noqa: E402


EXPECTED_SHA256 = "257b8a183c55b57ab59af56bfb6382c84496906c3cd67ce0556dd72f2df2fd2f"
MAGIC = b"HYFS\r\n\x1a\n"


def check(image):
    contents = image.read_bytes()
    actual_sha256 = hashlib.sha256(contents).hexdigest()
    assert actual_sha256 == EXPECTED_SHA256, (
        f"HyFS v1 fixture changed: {actual_sha256} != {EXPECTED_SHA256}"
    )
    assert len(contents) == 4 * 1024 * 1024
    superblock = contents[:512]
    directory = contents[512:1024]
    assert superblock[:8] == MAGIC
    assert struct.unpack_from("<IIQQIII", superblock, 8) == (
        1, 512, 8192, 1, 1, 2, zlib.crc32(directory)
    )
    stored_crc = struct.unpack_from("<I", superblock, 44)[0]
    assert stored_crc == zlib.crc32(superblock[:44] + b"\0\0\0\0")
    assert directory[24:32] == b"boot+txt"
    assert directory[88:97] == b"empty.txt"
    assert contents[1024:1029] == b"hello"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="copy the checked fixture here")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary) / "root"
        root.mkdir()
        (root / "boot+txt").write_bytes(b"hello")
        (root / "empty.txt").write_bytes(b"")
        image = Path(temporary) / "hyfs-v1.img"
        pack(root, image)
        check(image)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(image, args.output)
    print("Australis HyFS v1 fixture passed")


if __name__ == "__main__":
    main()
