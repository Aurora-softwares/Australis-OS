# HyFS v1 format and compatibility contract

HyFS v1 is Australis's legacy read-only bootstrap filesystem. The default OS
image now uses HyFS 2; build `make iso-hyfs1` for compatibility tests. A HyFS v1 partition has
one superblock, one flat directory allocation, and contiguous regular-file
extents. All integers are unsigned little-endian unless a field is described
otherwise. Filesystem block numbers are relative to the beginning of the GPT
partition and equal the device's logical sector size.

The partition is selected by GPT type GUID
`9f5eb82e-692e-5a8f-b968-adaaa349dd93`. The superblock version field,
rather than the partition type alone, distinguishes this format from later
HyFS revisions.

## Superblock: block 0

| Byte offset | Size | Meaning |
| --- | ---: | --- |
| 0 | 8 | Magic bytes `48 59 46 53 0d 0a 1a 0a` (`HYFS\r\n\x1a\n`) |
| 8 | 4 | Version, exactly `1` |
| 12 | 4 | Logical block size in bytes |
| 16 | 8 | Filesystem block count |
| 24 | 8 | First directory block |
| 32 | 4 | Directory block count |
| 36 | 4 | Count of 64-byte directory slots in use |
| 40 | 4 | CRC-32 of the complete directory allocation |
| 44 | 4 | CRC-32 of bytes 0–47 with bytes 44–47 treated as zero |
| 48 onward | Remainder of block | Zero-filled reserved bytes |

The logical block size must equal the block transport's sector size and be
between 512 and 4096 bytes. The filesystem block count must equal the GPT
partition block count. A valid partition has at least three blocks. The
directory starts at block 1 or later, occupies at least one block, stays
inside the partition, and is at most 128 blocks and 64 KiB. The number of
slots in use cannot exceed the allocation divided by 64. Bytes after the last
slot in the allocation are zero.

## Directory slots: 64 bytes each

| Byte offset in slot | Size | Meaning |
| --- | ---: | --- |
| 0 | 1 | Name length, 1–32 bytes for a file |
| 1 | 1 | Kind: `1` regular file; `0` empty slot |
| 2 | 2 | Flags, zero |
| 4 | 8 | First data block, or zero for an empty file |
| 12 | 8 | File length in bytes |
| 20 | 4 | CRC-32 of the exact file bytes, or zero for an empty file |
| 24 | 32 | Name bytes, then zero padding |
| 56 | 8 | Zero-filled reserved bytes |

An empty slot has all 64 bytes zero. The reader permits such a slot within
the slot count, although the v1 image packer emits only occupied slots.

File names are byte-exact, case-sensitive ASCII bytes `0x21`–`0x7e`, excluding
`/` (`0x2f`). Names `.` and `..` are reserved for path traversal and cannot
appear as directory entries. There are no subdirectories and names must be
unique across all occupied slots, including zero-length files. Lookup paths
are a slash followed by exactly one name; the VFS namespace normalizes paths
before handing a local path to HyFS.

A nonempty file uses `ceil(file_length / block_size)` consecutive blocks. Its
first data block must be at or after the end of the directory allocation, and
the whole extent must lie within the partition. Nonempty extents cannot
overlap. An empty file has length zero, first block zero, and CRC zero. File
CRC excludes padding in the last block.

CRC-32 here is the standard reflected CRC-32 used by `zlib.crc32`: initial
state `0xffffffff`, reflected polynomial `0xedb88320`, final XOR
`0xffffffff`, and the result stored little-endian.

## Reader behavior

The kernel rejects an invalid superblock or directory during mount. It
validates magic, version, geometry, both metadata CRCs, reserved fields,
names, duplicate names, extents, and padding. A read scans and checks the
complete file CRC before copying any requested bytes to the caller. A failed
read leaves the caller's destination unchanged. A slice past the end returns
end-of-file; a missing valid path returns not-found; a bad path returns an
invalid-argument result. The volume has no write operation.

The host image packer currently emits a 4 MiB, 512-byte-sector partition
image with the directory at block 1. It sorts source files by name, requires
at least one regular file, and rejects symlinks. The format reader can accept
other supported sector and partition sizes when the fields and extents are
valid.

## Compatibility fixture

`tests/vfs/hyfs_v1_fixture.py` creates a fixed image containing `boot+txt`
(`hello`) and `empty.txt` (empty). Its SHA-256 is
`257b8a183c55b57ab59af56bfb6382c84496906c3cd67ce0556dd72f2df2fd2f`.
The fixture test runs in `make test-hyfs1`. To save the verified image for a
future v2 reader test, run:

```bash
python3 tests/vfs/hyfs_v1_fixture.py --output build/hyfs-v1-compat.img
```
