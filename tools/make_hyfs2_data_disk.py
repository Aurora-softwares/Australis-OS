#!/usr/bin/env python3
"""Extend a HyFS 2 boot ISO into a raw GPT disk with a separate data volume."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import struct
import tempfile
import uuid
import zlib

from hyfs2 import Hyfs2Image


SECTOR = 512
BOOT_TYPE = uuid.UUID("9f5eb82e-692e-5a8f-b968-adaaa349dd93").bytes_le
DATA_TYPE = uuid.UUID("e9344e1c-1e85-5b78-9b94-488ef463fe7a").bytes_le
PROBE_MAGIC = b"HYFS2-BLOCK-PROBE\0"
DATA_BLOCKS = 16384  # 8 MiB, including the v2 filesystem's two superblocks.


def align(value: int, boundary: int) -> int:
    return (value + boundary - 1) // boundary * boundary


def read_gpt(image):
    image.seek(SECTOR)
    header = bytearray(image.read(SECTOR))
    if header[:8] != b"EFI PART" or struct.unpack_from("<I", header, 12)[0] != 92:
        raise ValueError("source ISO does not contain a supported GPT")
    if zlib.crc32(header[:16] + b"\0" * 4 + header[20:92]) != struct.unpack_from("<I", header, 16)[0]:
        raise ValueError("source GPT header CRC is invalid")
    entries_lba, count, size = struct.unpack_from("<QII", header, 72)
    if size != 128 or count < 6 or count > 256:
        raise ValueError("unsupported GPT entry array")
    image.seek(entries_lba * SECTOR)
    entries = bytearray(image.read(count * size))
    if len(entries) != count * size or zlib.crc32(entries) != struct.unpack_from("<I", header, 88)[0]:
        raise ValueError("source GPT entry CRC is invalid")
    if sum(entries[i * size:i * size + 16] == BOOT_TYPE for i in range(count)) != 1:
        raise ValueError("source must have exactly one HyFS boot partition")
    return header, entries


def write_header(image, template, entries, current, other, table_lba, last_usable):
    header = bytearray(template)
    struct.pack_into("<QQ", header, 24, current, other)
    struct.pack_into("<Q", header, 48, last_usable)
    struct.pack_into("<Q", header, 72, table_lba)
    struct.pack_into("<I", header, 88, zlib.crc32(entries))
    struct.pack_into("<I", header, 16, 0)
    struct.pack_into("<I", header, 16, zlib.crc32(header[:92]))
    image.seek(current * SECTOR)
    image.write(header)


def create(source: Path, output: Path, probe: bool = False):
    source = Path(source)
    output = Path(output)
    if output.exists():
        raise ValueError(f"output already exists: {output}")
    if source.stat().st_size % SECTOR:
        raise ValueError("source ISO size is not sector aligned")
    with source.open("rb") as image:
        template, entries = read_gpt(image)
    old_sectors = source.stat().st_size // SECTOR
    first = align(old_sectors + 1, 2048)
    last = first + DATA_BLOCKS - 1
    table_sectors = align(len(entries), SECTOR) // SECTOR
    backup_lba = last + table_sectors + 1
    backup_table = backup_lba - table_sectors
    if first <= struct.unpack_from("<Q", template, 48)[0]:
        raise ValueError("data volume overlaps source GPT usable range")
    empty = next((index for index in range(len(entries) // 128)
                  if not any(entries[index * 128:index * 128 + 16])), None)
    if empty is None:
        raise ValueError("GPT has no free entry")
    offset = empty * 128
    entries[offset:offset + 16] = DATA_TYPE
    entries[offset + 16:offset + 32] = uuid.uuid5(uuid.NAMESPACE_URL, "australis-hyfs2-data").bytes_le
    struct.pack_into("<QQ", entries, offset + 32, first, last)
    name = "HyFS 2 Data".encode("utf-16le")
    entries[offset + 56:offset + 56 + len(name)] = name
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".hyfs2-disk-", dir=output.parent, delete=False) as tmp:
            temporary = Path(tmp.name)
            with source.open("rb") as image:
                shutil.copyfileobj(image, tmp)
            tmp.truncate((backup_lba + 1) * SECTOR)
            with tempfile.TemporaryDirectory(prefix="hyfs2-volume-") as volume_dir:
                volume_path = Path(volume_dir) / "data.hyfs2"
                Hyfs2Image.create(volume_path, DATA_BLOCKS * SECTOR)
                with volume_path.open("r+b") as volume:
                    if probe:
                        volume.seek(3 * SECTOR)
                        volume.write(PROBE_MAGIC + bytes(SECTOR - len(PROBE_MAGIC)))
                with volume_path.open("rb") as volume:
                    tmp.seek(first * SECTOR)
                    shutil.copyfileobj(volume, tmp)
            tmp.seek(backup_table * SECTOR)
            tmp.write(entries)
            tmp.seek(2 * SECTOR)
            tmp.write(entries)
            write_header(tmp, template, entries, 1, backup_lba, 2, last)
            write_header(tmp, template, entries, backup_lba, 1, backup_table, last)
            tmp.seek(458)
            tmp.write(struct.pack("<I", min(backup_lba, 0xFFFFFFFF)))
            tmp.flush()
            os.fsync(tmp.fileno())
        os.replace(temporary, output)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    return first, DATA_BLOCKS


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--probe", action="store_true", help="seed the reserved test marker")
    arguments = parser.parse_args()
    start, count = create(arguments.source, arguments.output, arguments.probe)
    print(f"HyFS 2 data partition: LBA {start}, {count} sectors")
