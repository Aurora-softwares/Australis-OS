# HyFS v2 disk format (implementation contract)

HyFS v2 stores directories and regular files in a versioned, checksummed
snapshot. Boot volumes retain HyFS's GPT type GUID
`9f5eb82e-692e-5a8f-b968-adaaa349dd93`; the superblock version selects the
reader. The separate HyFS 2 data volume uses GPT type GUID
`e9344e1c-1e85-5b78-9b94-488ef463fe7a` and mounts at `/data`, so it cannot
be selected as the boot root. Both partition types contain this same v2 byte
format. All integers are unsigned little-endian. A block is one logical device
sector, initially 512 bytes. Block numbers are relative to the partition.
HyFS v2 is the default format produced by the Australis `make iso` target.

## Superblocks and commit

Blocks 0 and 1 are alternate superblock slots. Each has this layout:

| Offset | Size | Field |
| --- | ---: | --- |
| 0 | 8 | `HYFS\r\n\x1a\n` |
| 8 | 4 | Version `2` |
| 12 | 4 | Logical block size |
| 16 | 8 | Volume block count |
| 24 | 8 | Generation, starting at `1` |
| 32 | 8 | First object-table block |
| 40 | 4 | Object-table block count |
| 44 | 4 | Number of live object records |
| 48 | 4 | CRC-32 of the entire allocated object table |
| 52 | 4 | CRC-32 of bytes 0–55 with this field zeroed |
| 56 onward | Rest | Zero |

The reader selects the highest generation whose superblock, table, and file
contents all validate. If one slot is damaged, it can use the other. If both
are invalid, mount fails. Generations are limited to `2^63-1` and cannot wrap.
Timestamp values are likewise limited to `2^63-1` so the kernel and image tool
agree on their range. Unknown versions and
nonzero reserved bytes fail validation. A volume has at least 8 blocks. The
object table is at most 64 KiB, lies at or after block 2, and does not overlap
either superblock.

Updates use copy-on-write. The kernel and offline writers never overwrite blocks
in the selected snapshot or the other valid superblock generation before
committing. The kernel writer writes
changed file contents to unused blocks,
flushes, writes a new complete object table to unused blocks, flushes, then
writes the inactive superblock with the next generation and flushes. Failure
before that last step leaves the prior generation selected. A caller must
remount after an I/O failure because a failed physical write may have changed
part of its target block. No operation promises durability without a successful
device flush. If the final flush reports failure, remount can select either
the old or the new complete generation. The kernel does not retry a failed
write transaction in place. An explicit writable mount with only one valid
slot first copies the selected superblock to the inactive slot and flushes it;
failure leaves the volume unavailable for writes.

## Object table

The table is an array of 128-byte records sorted by strictly increasing,
nonzero object ID. Unused bytes in the final table block are zero. Its first
record is the root directory: ID 1, parent ID 0, kind 2, and an empty name.
IDs remain stable during updates; deleted IDs are not reused by the kernel
writer. New IDs exceed both the highest live ID and the current generation.
Writable mount requires the highest live ID to be no greater than generation
plus one, preserving that guarantee across deletion and remount. A volume
outside that rule remains readable but cannot be mounted writable. The 64 KiB
table limit permits at most 512 live objects.

| Offset in record | Size | Field |
| --- | ---: | --- |
| 0 | 4 | Object ID |
| 4 | 4 | Parent directory ID |
| 8 | 1 | Kind: `1` regular file, `2` directory |
| 9 | 1 | Name length, 0 for root and 1–63 otherwise |
| 10 | 2 | Metadata validity bits: 1 creation time, 2 modification time |
| 12 | 8 | First data block, or 0 for directory/empty file |
| 20 | 8 | File length, or 0 for directory |
| 28 | 4 | CRC-32 of exact file bytes, or 0 for directory/empty file |
| 32 | 8 | Creation time: Unix UTC seconds, 0 if unavailable |
| 40 | 8 | Modification time: Unix UTC seconds, 0 if unavailable |
| 48 | 4 | Attribute bits, initially 0 (no permissions implied) |
| 52 | 12 | Zero |
| 64 | 64 | ASCII name and zero padding |

Flags outside bits 0–1 and attribute bits outside the version's supported
mask are rejected. A time field is zero when its validity bit is clear; a
valid time can be zero (the Unix epoch). Owner, permissions, and access time
are deliberately absent until those concepts have defined system semantics.

Non-root names use printable ASCII bytes `0x21`–`0x7e`, excluding `/`, and
cannot be `.` or `..`. Names are case-sensitive and unique within a parent
directory. Every non-root parent must exist and be a directory. Parent links
must reach the root without a cycle. Empty directories require no data blocks.

Regular file data occupies `ceil(length / block_size)` contiguous blocks.
Its extent lies inside the volume and does not overlap the selected table,
superblocks, or any other live extent. Empty files have first block and CRC
zero. File CRC excludes padding in the final block. Directories have length,
first block, and data CRC zero. CRC-32 uses the same reflected algorithm as
HyFS v1 and `zlib.crc32`.

## Paths and API

The root path is `/`. The VFS normalizes repeated separators, `.`, and `..`
before filesystem lookup; traversal above `/` stays at `/`. A trailing slash
on a regular file is invalid. A resolved path names one object. Listing a
directory returns only its direct children. `Stat` returns kind, ID, byte
length, available timestamps, and attributes. File-format metadata such as
AUEX version and architecture belongs to the file's own header, not HyFS.

The kernel writer supports create, replace, append, truncate, delete, mkdir,
rmdir, and rename through an explicit writable mount. Append and truncate
copy the retained file prefix to a new extent; growing by truncate fills the
new bytes with zero. Deleting a nonempty directory, replacing a directory
with file data, and moving a directory below itself fail. These operations
publish one new generation only after all three flush points succeed.

The VFS opts in through `MountRootWritableAs`. Regular mounts remain read-only.
Writable file handles carry the mount identity, mount generation, object ID,
and VFS mutation generation. A later mutation makes other open handles stale;
the writer's own handle refreshes after a successful replace, append, or
truncate. A failed write that unmounts the HyFS 2 writer also invalidates the
VFS mount and its handles. Namespace rename rejects a move across volumes.
AUEX applications receive VFS status codes for mutations and checked opens;
metadata and directory queries expose errors through `Files.Status()`. Native
AUN1 calls expose bounded open/read/replace/append/close/create/delete through
separate process-owned descriptor tables and return negative VFS status codes.
New records have unavailable timestamps; content changes clear any prior
modification timestamp because the filesystem has no clock source of its own.
The boot and USB mounts remain read-only. A separately typed raw HyFS 2 data
partition mounts writable at `/data` by default. An I/O failure on a writable
volume invalidates that VFS mount and its open handles; remount verifies the
checksummed generations before another write is allowed.
