#!/usr/bin/env python3
"""Host checks for the HyFS v2 image format and offline CRUD operations."""

from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zlib


sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from hyfs2 import (  # noqa: E402
    Hyfs2Error, Hyfs2Image, KIND_DIRECTORY, KIND_FILE,
    CREATED_VALID, MODIFIED_VALID,
)


class Hyfs2ImageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "volume.img"
        self.image = Hyfs2Image.create(self.path, 1024 * 1024)

    def reopen(self):
        return Hyfs2Image.open(self.path)

    def test_nested_crud_and_metadata(self):
        self.image.mkdir("/Users")
        self.image.mkdir("/Users/Ada")
        self.image.put("/Users/Ada/note+1.txt", b"first")
        original = self.image.stat("/Users/Ada/note+1.txt")
        self.assertEqual(original.kind, KIND_FILE)
        self.assertEqual(original.length, 5)
        self.assertEqual(original.time_flags, CREATED_VALID | MODIFIED_VALID)
        self.assertGreater(original.created, 0)
        self.assertEqual(self.image.read_file("/Users/Ada/note+1.txt"), b"first")

        self.image.put("/Users/Ada/note+1.txt", b"updated content")
        updated = self.reopen().stat("/Users/Ada/note+1.txt")
        self.assertEqual(updated.object_id, original.object_id)
        self.assertEqual(updated.created, original.created)
        self.assertEqual(updated.length, 15)
        self.assertEqual(self.reopen().read_file("/Users/Ada/note+1.txt"),
                         b"updated content")

        self.image.move("/Users/Ada", "/Users/Grace")
        self.assertEqual(self.reopen().read_file("/Users/Grace/note+1.txt"),
                         b"updated content")
        self.assertEqual([(entry.name, entry.kind)
                          for entry in self.image.list_directory("/Users")],
                         [("Grace", KIND_DIRECTORY)])
        with self.assertRaises(Hyfs2Error):
            self.image.remove("/Users/Grace")
        self.image.remove("/Users/Grace/note+1.txt")
        self.image.remove("/Users/Grace")
        self.assertEqual(self.reopen().list_directory("/Users"), [])

    def test_empty_file_and_path_rules(self):
        self.image.mkdir("/Bin")
        self.image.put("/Bin/empty.exec", b"")
        entry = self.reopen().stat("/Bin/empty.exec")
        self.assertEqual((entry.length, entry.first_block, entry.data_crc),
                         (0, 0, 0))
        self.assertEqual(self.image.read_file("/Bin/empty.exec"), b"")
        self.assertEqual(self.image.stat("/Bin/../Bin//empty.exec").object_id,
                         entry.object_id)
        for path in ("/Bin/empty.exec/", "/Bin/missing", "/Bin/é", "Bin/file"):
            with self.assertRaises(Hyfs2Error):
                self.image.stat(path)
        with self.assertRaises(Hyfs2Error):
            self.image.move("/Bin", "/Bin/child")
        with self.assertRaises(Hyfs2Error):
            self.image.put("/Bin/new/", b"bytes")
        with self.assertRaises(Hyfs2Error):
            self.image.move("/Bin/empty.exec", "/Bin/renamed/")

    def test_interrupted_commit_preserves_previous_generation(self):
        self.image.put("/file", b"old data")
        before = self.image.snapshot.generation
        for point in ("after_data", "after_table"):
            with self.assertRaisesRegex(RuntimeError, "simulated interruption"):
                self.image.put("/file", b"new data", fail_at=point)
            remounted = self.reopen()
            self.assertEqual(remounted.snapshot.generation, before)
            self.assertEqual(remounted.read_file("/file"), b"old data")
        with self.assertRaisesRegex(RuntimeError, "simulated interruption"):
            self.image.put("/file", b"new data", fail_at="after_superblock")
        remounted = self.reopen()
        self.assertEqual(remounted.snapshot.generation, before + 1)
        self.assertEqual(remounted.read_file("/file"), b"new data")

    def test_corrupted_new_generation_falls_back(self):
        self.image.mkdir("/first")
        old_generation = self.image.snapshot.generation
        self.image.mkdir("/second")
        active_slot = self.image.snapshot.slot
        with self.path.open("r+b") as volume:
            volume.seek(active_slot * 512 + 48)
            volume.write(b"\0")
        recovered = self.reopen()
        self.assertEqual(recovered.snapshot.generation, old_generation)
        self.assertEqual([entry.name for entry in recovered.list_directory("/")],
                         ["first"])

    def test_rejects_invalid_updates_without_changing_disk(self):
        self.image.mkdir("/one")
        self.image.mkdir("/two")
        original = self.path.read_bytes()
        with self.assertRaises(Hyfs2Error):
            self.image.mkdir("/one")
        with self.assertRaises(Hyfs2Error):
            self.image.move("/one", "/two")
        with self.assertRaises(Hyfs2Error):
            self.image.put("/two", b"file")
        with self.assertRaises(Hyfs2Error):
            self.image.remove("/")
        self.assertEqual(self.path.read_bytes(), original)

    def test_stale_writer_cannot_replace_a_newer_generation(self):
        stale = self.reopen()
        self.image.put("/new", b"committed")
        current = self.path.read_bytes()
        with self.assertRaisesRegex(Hyfs2Error, "image changed"):
            stale.put("/other", b"stale")
        self.assertEqual(self.path.read_bytes(), current)
        self.assertEqual(self.reopen().read_file("/new"), b"committed")

    def test_out_of_space_preserves_committed_file(self):
        tiny_path = Path(self.temporary.name) / "tiny.img"
        tiny = Hyfs2Image.create(tiny_path, 8 * 512)
        tiny.put("/file", b"safe")
        before = tiny_path.read_bytes()
        with self.assertRaisesRegex(Hyfs2Error, "no contiguous free extent"):
            tiny.put("/file", b"x" * (8 * 512))
        self.assertEqual(tiny_path.read_bytes(), before)
        self.assertEqual(Hyfs2Image.open(tiny_path).read_file("/file"), b"safe")

    def test_import_directory_tree(self):
        source = Path(self.temporary.name) / "source"
        (source / "System" / "Core").mkdir(parents=True)
        (source / "System" / "Core" / "System.exec").write_bytes(b"AUEX")
        (source / "Temporary").mkdir()
        imported = Path(self.temporary.name) / "imported.img"
        image = Hyfs2Image.create(imported, 1024 * 1024, source)
        self.assertEqual(image.read_file("/System/Core/System.exec"), b"AUEX")
        self.assertEqual(image.list_directory("/Temporary"), [])

    def test_rejects_structurally_corrupt_tables(self):
        self.image.mkdir("/one")
        self.image.mkdir("/two")
        self.image.put("/a", b"first")
        self.image.put("/b", b"second")
        base = self.path.read_bytes()
        snapshot = self.image.snapshot
        record = {entry.name: index * 128 for index, entry in
                  enumerate(snapshot.entries)}
        table_start = snapshot.table_first * 512
        table_length = snapshot.table_blocks * 512
        header_start = snapshot.slot * 512

        def rejected(mutate):
            data = bytearray(base)
            # Isolate the malformed generation so a previous valid snapshot
            # cannot legitimately be selected as a recovery fallback.
            data[(1 - snapshot.slot) * 512:(2 - snapshot.slot) * 512] = bytes(512)
            mutate(data, table_start, record)
            table = data[table_start:table_start + table_length]
            struct.pack_into("<I", data, header_start + 48, zlib.crc32(table))
            struct.pack_into("<I", data, header_start + 52, 0)
            struct.pack_into("<I", data, header_start + 52,
                             zlib.crc32(data[header_start:header_start + 56]))
            self.path.write_bytes(data)
            with self.assertRaises(Hyfs2Error):
                self.reopen()

        rejected(lambda data, start, row: data.__setitem__(
            slice(start + row["two"] + 64, start + row["two"] + 67), b"one"))
        rejected(lambda data, start, row: struct.pack_into(
            "<I", data, start + row["one"] + 4,
            self.image.stat("/one").object_id))
        rejected(lambda data, start, row: struct.pack_into(
            "<H", data, start + row["one"] + 10, 4))
        rejected(lambda data, start, row: struct.pack_into(
            "<Q", data, start + row["b"] + 12,
            self.image.stat("/a").first_block))
        rejected(lambda data, start, row: struct.pack_into(
            "<Q", data, start + row["b"] + 12,
            self.image.volume_blocks))


if __name__ == "__main__":
    unittest.main()
