#!/usr/bin/env python3
"""Pack a flat directory into a read-only HyFS v1 partition image."""

import argparse
from pathlib import Path
import struct
import zlib


SECTOR_SIZE = 512
# 4 MiB partition
VOLUME_BYTES = 4 * 1024 * 1024
ENTRY_BYTES = 64
MAX_DIRECTORY_BYTES = 65536
MAGIC = b"HYFS\r\n\x1a\n"


def blocks_for(byte_count):
    return (byte_count + SECTOR_SIZE - 1) // SECTOR_SIZE


def source_files(root):
    if not root.is_dir():
        raise ValueError(f"root directory does not exist: {root}")
    files = []
    for path in sorted(root.iterdir()):
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"HyFS v1 accepts only regular files: {path}")
        name = path.name.encode("ascii")
        if not 1 <= len(name) <= 32 or any(byte < 33 or byte > 126 or byte == 47 for byte in name):
            raise ValueError(f"invalid HyFS v1 file name: {path.name}")
        files.append((name, path.read_bytes()))
    if not files:
        raise ValueError("HyFS root must contain at least one file")
    return files


def pack(root, output):
    files = source_files(root)
    directory_blocks = max(1, blocks_for(len(files) * ENTRY_BYTES))
    if directory_blocks * SECTOR_SIZE > MAX_DIRECTORY_BYTES:
        raise ValueError("HyFS directory exceeds 64 KiB")
    block_count = VOLUME_BYTES // SECTOR_SIZE
    next_block = 1 + directory_blocks
    directory = bytearray(directory_blocks * SECTOR_SIZE)
    extents = []

    for index, (name, contents) in enumerate(files):
        offset = index * ENTRY_BYTES
        directory[offset] = len(name)
        directory[offset + 1] = 1  # regular file
        first_block = next_block if contents else 0
        struct.pack_into("<QQI", directory, offset + 4, first_block, len(contents), zlib.crc32(contents) if contents else 0)
        directory[offset + 24:offset + 24 + len(name)] = name
        if contents:
            next_block += blocks_for(len(contents))
            extents.append((first_block, contents))
    if next_block > block_count:
        raise ValueError("HyFS files exceed the 4 MiB partition")

    superblock = bytearray(SECTOR_SIZE)
    superblock[:8] = MAGIC
    struct.pack_into("<IIQQIII", superblock, 8, 1, SECTOR_SIZE, block_count, 1,
                     directory_blocks, len(files), zlib.crc32(directory))
    struct.pack_into("<I", superblock, 44, zlib.crc32(superblock[:48]))

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as image:
        image.truncate(VOLUME_BYTES)
        image.write(superblock)
        image.write(directory)
        for first_block, contents in extents:
            image.seek(first_block * SECTOR_SIZE)
            image.write(contents)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    pack(arguments.root, arguments.output)


if __name__ == "__main__":
    main()
