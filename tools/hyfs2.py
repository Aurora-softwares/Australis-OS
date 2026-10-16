#!/usr/bin/env python3
"""Create, inspect, and edit HyFS v2 images with copy-on-write commits."""

from __future__ import annotations

import argparse
from dataclasses import dataclass, replace
import os
from pathlib import Path
import struct
import time
import zlib


MAGIC = b"HYFS\r\n\x1a\n"
VERSION = 2
BLOCK_SIZE = 512
ENTRY_SIZE = 128
MAX_TABLE_BYTES = 65536
MAX_PATH_BYTES = 255
MAX_SIGNED64 = 0x7FFFFFFFFFFFFFFF
KIND_FILE = 1
KIND_DIRECTORY = 2
CREATED_VALID = 1
MODIFIED_VALID = 2


class Hyfs2Error(ValueError):
    """Invalid image, path, or operation."""


def blocks_for(length: int) -> int:
    return (length + BLOCK_SIZE - 1) // BLOCK_SIZE


def name_bytes(name: str, root: bool = False) -> bytes:
    try:
        data = name.encode("ascii")
    except UnicodeEncodeError as error:
        raise Hyfs2Error("HyFS v2 names must be ASCII") from error
    if root and data == b"":
        return data
    if not 1 <= len(data) <= 63 or data in (b".", b"..") or any(
        byte < 33 or byte > 126 or byte == 47 for byte in data
    ):
        raise Hyfs2Error(f"invalid HyFS v2 name: {name!r}")
    return data


def components(path: str) -> list[str]:
    if not path.startswith("/"):
        raise Hyfs2Error("path must be absolute")
    try:
        encoded = path.encode("ascii")
    except UnicodeEncodeError as error:
        raise Hyfs2Error("HyFS v2 paths must be ASCII") from error
    if len(encoded) > MAX_PATH_BYTES:
        raise Hyfs2Error("path exceeds 255 bytes")
    result: list[str] = []
    for part in path.split("/"):
        if not part or part == ".":
            continue
        if part == "..":
            if result:
                result.pop()
            continue
        name_bytes(part)
        result.append(part)
    return result


@dataclass(frozen=True)
class Entry:
    object_id: int
    parent_id: int
    kind: int
    name: str
    first_block: int = 0
    length: int = 0
    data_crc: int = 0
    created: int = 0
    modified: int = 0
    time_flags: int = 0
    attributes: int = 0

    def encode(self) -> bytes:
        raw_name = name_bytes(self.name, self.object_id == 1)
        result = bytearray(ENTRY_SIZE)
        struct.pack_into("<IIBBHQQIQQI", result, 0, self.object_id,
                         self.parent_id, self.kind, len(raw_name),
                         self.time_flags, self.first_block, self.length,
                         self.data_crc, self.created, self.modified,
                         self.attributes)
        result[64:64 + len(raw_name)] = raw_name
        return bytes(result)

    @staticmethod
    def decode(data: bytes) -> Entry:
        if len(data) != ENTRY_SIZE or any(data[52:64]):
            raise Hyfs2Error("invalid object record padding")
        (object_id, parent_id, kind, name_length, time_flags,
         first_block, length, data_crc, created, modified,
         attributes) = struct.unpack_from("<IIBBHQQIQQI", data)
        if name_length > 63 or any(data[64 + name_length:128]):
            raise Hyfs2Error("invalid object name padding")
        try:
            name = data[64:64 + name_length].decode("ascii")
        except UnicodeDecodeError as error:
            raise Hyfs2Error("invalid object name") from error
        name_bytes(name, object_id == 1)
        if kind not in (KIND_FILE, KIND_DIRECTORY) or time_flags & ~3:
            raise Hyfs2Error("invalid object kind or metadata flags")
        if attributes != 0:
            raise Hyfs2Error("unsupported object attributes")
        if created > MAX_SIGNED64 or modified > MAX_SIGNED64:
            raise Hyfs2Error("unsupported timestamp range")
        if not time_flags & CREATED_VALID and created != 0:
            raise Hyfs2Error("creation time lacks validity flag")
        if not time_flags & MODIFIED_VALID and modified != 0:
            raise Hyfs2Error("modification time lacks validity flag")
        return Entry(object_id, parent_id, kind, name, first_block, length,
                     data_crc, created, modified, time_flags, attributes)


@dataclass(frozen=True)
class Snapshot:
    generation: int
    slot: int
    table_first: int
    table_blocks: int
    entries: tuple[Entry, ...]


def superblock(generation: int, volume_blocks: int, table_first: int,
               table_blocks: int, entries: int, table_crc: int) -> bytes:
    header = bytearray(BLOCK_SIZE)
    header[:8] = MAGIC
    struct.pack_into("<IIQQQIII", header, 8, VERSION, BLOCK_SIZE,
                     volume_blocks, generation, table_first, table_blocks,
                     entries, table_crc)
    struct.pack_into("<I", header, 52, zlib.crc32(header[:56]))
    return bytes(header)


class Hyfs2Image:
    def __init__(self, path: Path, volume_blocks: int, snapshot: Snapshot):
        self.path = Path(path)
        self.volume_blocks = volume_blocks
        self.snapshot = snapshot
        self.entries = {entry.object_id: entry for entry in snapshot.entries}

    @classmethod
    def create(cls, path: Path, size_bytes: int = 4 * 1024 * 1024,
               source: Path | None = None) -> Hyfs2Image:
        path = Path(path)
        if size_bytes < 8 * BLOCK_SIZE or size_bytes % BLOCK_SIZE:
            raise Hyfs2Error("size must be a sector multiple of at least 4096 bytes")
        if path.exists():
            raise Hyfs2Error(f"image already exists: {path}")
        if source is not None:
            source = Path(source)
            if not source.is_dir() or source.is_symlink():
                raise Hyfs2Error("source must be a real directory")
        path.parent.mkdir(parents=True, exist_ok=True)
        root = Entry(1, 0, KIND_DIRECTORY, "")
        table = root.encode() + bytes(BLOCK_SIZE - ENTRY_SIZE)
        with path.open("xb") as image:
            image.truncate(size_bytes)
            image.seek(2 * BLOCK_SIZE)
            image.write(table)
            image.flush()
            os.fsync(image.fileno())
            # Format both slots so the first writable mount needs no repair I/O.
            header = superblock(1, size_bytes // BLOCK_SIZE, 2, 1, 1,
                                zlib.crc32(table))
            image.seek(0)
            image.write(header)
            image.write(header)
            image.flush()
            os.fsync(image.fileno())
        result = cls.open(path)
        if source is not None:
            try:
                result.import_tree(source)
            except Exception:
                path.unlink()
                raise
        return result

    @classmethod
    def open(cls, path: Path) -> Hyfs2Image:
        path = Path(path)
        size = path.stat().st_size
        if size < 8 * BLOCK_SIZE or size % BLOCK_SIZE:
            raise Hyfs2Error("invalid image size")
        volume_blocks = size // BLOCK_SIZE
        candidates: list[Snapshot] = []
        with path.open("rb") as image:
            for slot in (0, 1):
                try:
                    candidates.append(cls._read_snapshot(image, slot, volume_blocks))
                except Hyfs2Error:
                    pass
        if not candidates:
            raise Hyfs2Error("no valid HyFS v2 generation")
        chosen = max(candidates, key=lambda snapshot: snapshot.generation)
        return cls(path, volume_blocks, chosen)

    @staticmethod
    def _read_snapshot(image, slot: int, volume_blocks: int) -> Snapshot:
        image.seek(slot * BLOCK_SIZE)
        header = image.read(BLOCK_SIZE)
        if len(header) != BLOCK_SIZE or header[:8] != MAGIC or any(header[56:]):
            raise Hyfs2Error("invalid superblock")
        (version, block_size, stored_blocks, generation, table_first,
         table_blocks, entry_count, table_crc, header_crc) = struct.unpack_from(
             "<IIQQQIIII", header, 8
         )
        if version != VERSION or block_size != BLOCK_SIZE or stored_blocks != volume_blocks:
            raise Hyfs2Error("unsupported geometry or version")
        if header_crc != zlib.crc32(header[:52] + b"\0\0\0\0"):
            raise Hyfs2Error("bad superblock CRC")
        if (generation < 1 or generation > MAX_SIGNED64 or table_first < 2 or
                table_blocks < 1 or table_blocks * BLOCK_SIZE > MAX_TABLE_BYTES or
                table_first + table_blocks > volume_blocks or entry_count < 1 or
                entry_count > MAX_TABLE_BYTES // ENTRY_SIZE or
                blocks_for(entry_count * ENTRY_SIZE) != table_blocks):
            raise Hyfs2Error("invalid object table location")
        image.seek(table_first * BLOCK_SIZE)
        table = image.read(table_blocks * BLOCK_SIZE)
        if len(table) != table_blocks * BLOCK_SIZE or zlib.crc32(table) != table_crc:
            raise Hyfs2Error("bad object table CRC")
        if any(table[entry_count * ENTRY_SIZE:]):
            raise Hyfs2Error("nonzero object table padding")
        entries = tuple(Entry.decode(table[i * ENTRY_SIZE:(i + 1) * ENTRY_SIZE])
                        for i in range(entry_count))
        Hyfs2Image._validate_entries(image, entries, volume_blocks,
                                     table_first, table_blocks)
        return Snapshot(generation, slot, table_first, table_blocks, entries)

    @staticmethod
    def _validate_entries(image, entries: tuple[Entry, ...], volume_blocks: int,
                          table_first: int, table_blocks: int) -> None:
        if entries[0] != Entry(1, 0, KIND_DIRECTORY, ""):
            # Timestamps on root are allowed, but structural fields are fixed.
            root = entries[0]
            if (root.object_id != 1 or root.parent_id != 0 or
                root.kind != KIND_DIRECTORY or root.name != "" or
                root.first_block or root.length or root.data_crc):
                raise Hyfs2Error("invalid root")
        by_id = {entry.object_id: entry for entry in entries}
        if len(by_id) != len(entries) or list(by_id) != sorted(by_id):
            raise Hyfs2Error("object IDs must be unique and sorted")
        names: set[tuple[int, str]] = set()
        occupied = set((0, 1)) | set(range(table_first, table_first + table_blocks))
        for entry in entries:
            if entry.object_id < 1:
                raise Hyfs2Error("invalid object ID")
            if entry.object_id != 1:
                parent = by_id.get(entry.parent_id)
                if parent is None or parent.kind != KIND_DIRECTORY:
                    raise Hyfs2Error("invalid parent directory")
                key = (entry.parent_id, entry.name)
                if key in names:
                    raise Hyfs2Error("duplicate directory name")
                names.add(key)
                seen = {entry.object_id}
                ancestor = parent
                while ancestor.object_id != 1:
                    if ancestor.object_id in seen:
                        raise Hyfs2Error("directory cycle")
                    seen.add(ancestor.object_id)
                    ancestor = by_id.get(ancestor.parent_id)
                    if ancestor is None or ancestor.kind != KIND_DIRECTORY:
                        raise Hyfs2Error("orphaned object")
            if entry.kind == KIND_DIRECTORY:
                if entry.first_block or entry.length or entry.data_crc:
                    raise Hyfs2Error("directory has file data")
                continue
            if entry.length == 0:
                if entry.first_block or entry.data_crc:
                    raise Hyfs2Error("empty file has an extent")
                continue
            count = blocks_for(entry.length)
            if entry.first_block < 2 or entry.first_block + count > volume_blocks:
                raise Hyfs2Error("file extent outside volume")
            blocks = set(range(entry.first_block, entry.first_block + count))
            if blocks & occupied:
                raise Hyfs2Error("overlapping file extent")
            occupied.update(blocks)
            image.seek(entry.first_block * BLOCK_SIZE)
            remaining = entry.length
            crc = 0
            while remaining:
                chunk = image.read(min(remaining, 65536))
                if not chunk:
                    raise Hyfs2Error("truncated file extent")
                crc = zlib.crc32(chunk, crc)
                remaining -= len(chunk)
            if crc != entry.data_crc:
                raise Hyfs2Error("bad file data CRC")

    def _lookup(self, path: str) -> Entry:
        current = self.entries[1]
        for part in components(path):
            if current.kind != KIND_DIRECTORY:
                raise Hyfs2Error("path traverses a regular file")
            match = next((entry for entry in self.entries.values()
                          if entry.parent_id == current.object_id and entry.name == part), None)
            if match is None:
                raise Hyfs2Error(f"path not found: {path}")
            current = match
        if path.endswith("/") and current.kind != KIND_DIRECTORY:
            raise Hyfs2Error("regular file path has trailing slash")
        return current

    def stat(self, path: str) -> Entry:
        return self._lookup(path)

    def list_directory(self, path: str) -> list[Entry]:
        parent = self._lookup(path)
        if parent.kind != KIND_DIRECTORY:
            raise Hyfs2Error("path is not a directory")
        return sorted((entry for entry in self.entries.values()
                       if entry.parent_id == parent.object_id),
                      key=lambda entry: entry.name)

    def read_file(self, path: str) -> bytes:
        entry = self._lookup(path)
        if entry.kind != KIND_FILE:
            raise Hyfs2Error("path is not a regular file")
        if not entry.length:
            return b""
        with self.path.open("rb") as image:
            image.seek(entry.first_block * BLOCK_SIZE)
            contents = image.read(entry.length)
        if len(contents) != entry.length or zlib.crc32(contents) != entry.data_crc:
            raise Hyfs2Error("file data changed after mount")
        return contents

    def _parent_and_name(self, path: str) -> tuple[Entry, str]:
        parts = components(path)
        if not parts:
            raise Hyfs2Error("cannot modify root")
        parent_path = "/" + "/".join(parts[:-1])
        parent = self._lookup(parent_path)
        if parent.kind != KIND_DIRECTORY:
            raise Hyfs2Error("parent is not a directory")
        return parent, parts[-1]

    def _used_blocks(self) -> set[int]:
        used = {0, 1}
        used.update(range(self.snapshot.table_first,
                          self.snapshot.table_first + self.snapshot.table_blocks))
        for entry in self.entries.values():
            if entry.kind == KIND_FILE and entry.length:
                used.update(range(entry.first_block,
                                  entry.first_block + blocks_for(entry.length)))
        return used

    def _allocate(self, count: int, used: set[int]) -> int:
        if count == 0:
            return 0
        first = 2
        while first + count <= self.volume_blocks:
            if all(block not in used for block in range(first, first + count)):
                used.update(range(first, first + count))
                return first
            first += 1
        raise Hyfs2Error("volume has no contiguous free extent")

    def _commit(self, proposed: dict[int, Entry], changed_data: dict[int, bytes] | None = None,
                fail_at: str | None = None) -> None:
        if self.snapshot.generation == MAX_SIGNED64:
            raise Hyfs2Error("generation exhausted")
        if max(proposed) > 0xFFFFFFFF:
            raise Hyfs2Error("object IDs exhausted")
        changed_data = changed_data or {}
        used = self._used_blocks()
        proposed = dict(proposed)
        writes = []
        for object_id, contents in changed_data.items():
            first = self._allocate(blocks_for(len(contents)), used)
            proposed[object_id] = replace(proposed[object_id], first_block=first,
                                          length=len(contents),
                                          data_crc=zlib.crc32(contents) if contents else 0)
            if contents:
                writes.append((first, contents))
        ordered = tuple(proposed[key] for key in sorted(proposed))
        if len(ordered) * ENTRY_SIZE > MAX_TABLE_BYTES:
            raise Hyfs2Error("object table is full")
        table_bytes = b"".join(entry.encode() for entry in ordered)
        table_blocks = blocks_for(len(table_bytes))
        table_bytes += bytes(table_blocks * BLOCK_SIZE - len(table_bytes))
        table_first = self._allocate(table_blocks, used)
        # Validate the proposed tree before touching the image.
        self._validate_structure(ordered, table_first, table_blocks)
        current = Hyfs2Image.open(self.path).snapshot
        if (current.generation != self.snapshot.generation or
                current.slot != self.snapshot.slot or
                current.table_first != self.snapshot.table_first):
            raise Hyfs2Error("image changed; reopen before editing")
        inactive = 1 - self.snapshot.slot
        with self.path.open("r+b") as image:
            for first, contents in writes:
                image.seek(first * BLOCK_SIZE)
                image.write(contents)
            image.flush()
            os.fsync(image.fileno())
            if fail_at == "after_data":
                raise RuntimeError("simulated interruption after file data")
            image.seek(table_first * BLOCK_SIZE)
            image.write(table_bytes)
            image.flush()
            os.fsync(image.fileno())
            if fail_at == "after_table":
                raise RuntimeError("simulated interruption after object table")
            image.seek(inactive * BLOCK_SIZE)
            image.write(superblock(self.snapshot.generation + 1,
                                   self.volume_blocks, table_first, table_blocks,
                                   len(ordered), zlib.crc32(table_bytes)))
            image.flush()
            os.fsync(image.fileno())
            if fail_at == "after_superblock":
                raise RuntimeError("simulated interruption after commit")
        self.snapshot = Snapshot(self.snapshot.generation + 1, inactive,
                                 table_first, table_blocks, ordered)
        self.entries = proposed

    def _validate_structure(self, entries: tuple[Entry, ...], table_first: int,
                            table_blocks: int) -> None:
        # Validate metadata without reading newly allocated data that has not
        # yet been written. Mount performs the complete on-disk CRC check.
        by_id = {entry.object_id: entry for entry in entries}
        if len(by_id) != len(entries) or 1 not in by_id:
            raise Hyfs2Error("invalid proposed object IDs")
        names = set()
        occupied = {0, 1} | set(range(table_first, table_first + table_blocks))
        for entry in entries:
            Entry.decode(entry.encode())
            if entry.object_id == 1:
                if entry.parent_id or entry.kind != KIND_DIRECTORY or entry.name:
                    raise Hyfs2Error("invalid root")
            else:
                parent = by_id.get(entry.parent_id)
                if parent is None or parent.kind != KIND_DIRECTORY:
                    raise Hyfs2Error("invalid parent")
                key = (entry.parent_id, entry.name)
                if key in names:
                    raise Hyfs2Error("duplicate name")
                names.add(key)
                seen = {entry.object_id}
                while parent.object_id != 1:
                    if parent.object_id in seen:
                        raise Hyfs2Error("directory cycle")
                    seen.add(parent.object_id)
                    parent = by_id.get(parent.parent_id)
                    if parent is None or parent.kind != KIND_DIRECTORY:
                        raise Hyfs2Error("orphaned object")
            if entry.kind == KIND_DIRECTORY:
                if entry.first_block or entry.length or entry.data_crc:
                    raise Hyfs2Error("directory has file data")
            elif entry.length:
                count = blocks_for(entry.length)
                if entry.first_block < 2 or entry.first_block + count > self.volume_blocks:
                    raise Hyfs2Error("extent outside volume")
                blocks = set(range(entry.first_block, entry.first_block + count))
                if blocks & occupied:
                    raise Hyfs2Error("extent collision")
                occupied.update(blocks)
            elif entry.first_block or entry.data_crc:
                raise Hyfs2Error("empty file has an extent")

    def mkdir(self, path: str, fail_at: str | None = None,
              record_time: bool = True) -> None:
        parent, name = self._parent_and_name(path)
        if any(entry.parent_id == parent.object_id and entry.name == name
               for entry in self.entries.values()):
            raise Hyfs2Error("entry already exists")
        object_id = max(self.entries) + 1
        now = int(time.time()) if record_time else 0
        proposed = dict(self.entries)
        proposed[object_id] = Entry(object_id, parent.object_id, KIND_DIRECTORY,
                                    name, created=now, modified=now,
                                    time_flags=3 if record_time else 0)
        self._commit(proposed, fail_at=fail_at)

    def put(self, path: str, contents: bytes, fail_at: str | None = None,
            record_time: bool = True) -> None:
        if path != "/" and path.endswith("/"):
            raise Hyfs2Error("regular file path has trailing slash")
        parent, name = self._parent_and_name(path)
        existing = next((entry for entry in self.entries.values()
                         if entry.parent_id == parent.object_id and entry.name == name), None)
        if existing is not None and existing.kind != KIND_FILE:
            raise Hyfs2Error("cannot replace a directory with a file")
        now = int(time.time()) if record_time else 0
        object_id = existing.object_id if existing else max(self.entries) + 1
        created = existing.created if existing else now
        flags = (existing.time_flags & CREATED_VALID) if existing else (
            CREATED_VALID if record_time else 0
        )
        proposed = dict(self.entries)
        proposed[object_id] = Entry(object_id, parent.object_id, KIND_FILE, name,
                                    created=created, modified=now,
                                    time_flags=flags | (MODIFIED_VALID if record_time else 0))
        self._commit(proposed, {object_id: contents}, fail_at)

    def remove(self, path: str, fail_at: str | None = None) -> None:
        entry = self._lookup(path)
        if entry.object_id == 1:
            raise Hyfs2Error("cannot remove root")
        if entry.kind == KIND_DIRECTORY and any(
            child.parent_id == entry.object_id for child in self.entries.values()
        ):
            raise Hyfs2Error("directory is not empty")
        proposed = dict(self.entries)
        del proposed[entry.object_id]
        self._commit(proposed, fail_at=fail_at)

    def move(self, source: str, destination: str, fail_at: str | None = None) -> None:
        entry = self._lookup(source)
        if entry.object_id == 1:
            raise Hyfs2Error("cannot move root")
        if entry.kind == KIND_FILE and destination.endswith("/"):
            raise Hyfs2Error("regular file path has trailing slash")
        parent, name = self._parent_and_name(destination)
        if any(item.parent_id == parent.object_id and item.name == name
               for item in self.entries.values()):
            raise Hyfs2Error("destination exists")
        proposed = dict(self.entries)
        proposed[entry.object_id] = replace(entry, parent_id=parent.object_id,
                                            name=name, modified=int(time.time()),
                                            time_flags=entry.time_flags | MODIFIED_VALID)
        self._commit(proposed, fail_at=fail_at)

    def import_tree(self, source: Path, parent_path: str = "/") -> None:
        for child in sorted(source.iterdir(), key=lambda item: item.name):
            if child.is_symlink():
                raise Hyfs2Error(f"symlinks are unsupported: {child}")
            destination = parent_path.rstrip("/") + "/" + child.name
            if child.is_dir():
                self.mkdir(destination, record_time=False)
                self.import_tree(child, destination)
            elif child.is_file():
                self.put(destination, child.read_bytes(), record_time=False)
            else:
                raise Hyfs2Error(f"unsupported source type: {child}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    create = sub.add_parser("create")
    create.add_argument("image", type=Path)
    create.add_argument("--size-mib", type=int, default=4)
    create.add_argument("--source", type=Path)
    for operation in ("ls", "stat", "cat", "mkdir", "rm"):
        command = sub.add_parser(operation)
        command.add_argument("image", type=Path)
        command.add_argument("path")
    put = sub.add_parser("put")
    put.add_argument("image", type=Path)
    put.add_argument("source", type=Path)
    put.add_argument("path")
    move = sub.add_parser("mv")
    move.add_argument("image", type=Path)
    move.add_argument("source")
    move.add_argument("destination")
    args = parser.parse_args()
    try:
        if args.command == "create":
            Hyfs2Image.create(args.image, args.size_mib * 1024 * 1024, args.source)
            return
        image = Hyfs2Image.open(args.image)
        if args.command == "ls":
            for entry in image.list_directory(args.path):
                print(("d " if entry.kind == KIND_DIRECTORY else "f ") + entry.name)
        elif args.command == "stat":
            print(image.stat(args.path))
        elif args.command == "cat":
            os.write(1, image.read_file(args.path))
        elif args.command == "mkdir":
            image.mkdir(args.path)
        elif args.command == "rm":
            image.remove(args.path)
        elif args.command == "put":
            image.put(args.path, args.source.read_bytes())
        elif args.command == "mv":
            image.move(args.source, args.destination)
    except (Hyfs2Error, OSError) as error:
        parser.exit(1, f"hyfs2: {error}\n")


if __name__ == "__main__":
    main()
