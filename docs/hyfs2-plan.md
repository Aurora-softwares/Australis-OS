# HyFS 2 implementation plan

## Decision and current state

HyFS v1 is a deliberately read-only bootstrap format: one flat directory of
regular files, a checked superblock and directory, file lengths and CRC-32s,
and bounded reads through the VFS. It already boots from AHCI and NVMe and can
be mounted from USB. The existing `make test-hyfs` and `make test-vfs` host
tests pass as of 11 October 2026. This is substantially complete **for its
stated v1 scope**. Folders, persistent writes, timestamps, owners, and
permissions were never v1 features.

The v1 correctness and compatibility closeout below is complete. Build HyFS 2
as a new, versioned on-disk format. Keep the v1 reader for older boot and
recovery images until HyFS 2 has passed its boot and corruption tests.

**Implementation update (11 October 2026):** The v2 disk layout, offline
copy-on-write CRUD tool, kernel reader, richer VFS metadata, and nested shell
listing are implemented. The v2 image boots and traverses on AHCI and NVMe.
A separate raw GPT disk has a typed HyFS 2 data partition at `/data`.
Disposable live tests write nine sectors, flush, reboot, and verify persistence
on AHCI and NVMe; both inject write failures and reboot the failed disk to
verify a later successful write persists. AHCI's backend flush error
is injected live. QEMU's NVMe emulation does not forward the blkdebug flush
fault to its namespace backend, so NVMe flush rejection remains host tested.
Normal kernel filesystem mounts are still read-only. The kernel's explicit
HyFS 2 writer implements all planned mutations, with host remount and fault
tests. The VFS has an explicit writable-mount policy and checked mutation
handles. AUEX has file, metadata, and directory calls, including a working
Inspector example. Broader live recovery checks remain before the data
volume can accept persistent writes by default.

### HyFS v1 closeout

- [x] Read-only image packer and kernel reader for flat regular files.
- [x] Superblock, directory, extent, and complete-file CRC validation.
- [x] Host VFS/HyFS tests and live AHCI/NVMe boot and read paths.
- [x] Reject duplicate names even when the later file is empty; test both an
  empty file matching a nonempty file and two identically named empty files.
- [x] Make path lookup accept the full printable ASCII name set emitted by
  the packer, and reject `.` and `..` entries that cannot be reached as files.
- [x] Run host tests and AHCI/NVMe boot checks. Pin a generated v1 image with
  a stable checksum for future reader compatibility checks.
- [x] Publish the final v1 byte layout and validation rules in `docs/hyfs-v1.md`.

**v1 exit check passed:** a known-good v1 image still mounts and reads; malformed
images, including duplicate empty names, fail without exposing partial data.

## HyFS 2 goals and boundaries

HyFS 2 should support nested directories, regular files, explicit metadata,
checked reads, and eventually safe persistent writes. The first HyFS 2 image
can remain read-only. A writable filesystem requires working block writes,
durability, allocation, and recovery in addition to a new directory layout.

Keep file content separate from filesystem metadata. HyFS can report a file's
name, kind, size, timestamps, and attributes when known. The application
inspector reads an AUEX or other file header to report its format version,
entry point, target architecture, and embedded checksums. Unknown metadata
must have an explicit unavailable state instead of invented values.

The current ISO-backed root and USB test volumes are opened read-only or with
QEMU snapshots. Persistent-write testing needs a writable raw disk or a
separate writable data partition. Booting the existing recovery image can
remain independent of that writable volume.

## Milestone 1: freeze the on-disk contract

- [x] Write a byte-accurate HyFS 2 specification: magic, version,
  feature flags, block size, volume size, root identifier, metadata locations,
  checksums, endianness, and reserved-field behavior.
- [x] Define stable object identifiers and directory entries that connect a
  parent directory to a named child. Specify regular file and directory kinds,
  root handling, empty directories, and hard limits on depth and name length.
- [x] Define name encoding and comparison once. Choose and document an initial
  bounded subset if full UTF-8 handling is not yet supported; reject malformed
  names and duplicate names within one directory.
- [x] Define path behavior: absolute paths, `/`, `.`, `..`, repeated `/`,
  trailing `/`, maximum path length, and attempted traversal above root.
  Specify how VFS mount points such as `/usb` interact with traversal.
- [x] Define file size and allocation records, free-space tracking, and rules
  against overlapping extents, cycles, orphaned records, and out-of-volume
  pointers. State maximum file and directory sizes. Make volume size a format
  parameter instead of inheriting the v1 packer's fixed 4 MiB image.
- [x] Define the metadata record: kind, byte length, optional creation and
  modification times, attributes, and validity flags. Decide whether owner
  and permissions have real meaning yet; omit them until an identity and
  access-control model exists. Avoid persistent access-time updates initially.
- [x] Specify integrity coverage for superblocks, allocation metadata,
  directories, and file contents. Distinguish corruption from I/O failure.
- [x] Define version dispatch: reject unknown incompatible features; mount v1
  through the v1 reader and v2 through the v2 reader. Decide whether v2 uses
  the existing GPT partition type GUID or a new one, and document that choice.
- [x] Create a checksum-pinned binary fixture and format conformance tests
  for the kernel reader.

**Exit check:** two independent parsers can read the same fixture and agree on
all paths, metadata, file bytes, and invalid-image cases.

## Milestone 2: read-only HyFS 2 image and kernel support

- [x] Extend `tools/make_hyfs_image.py` or add a v2 packer that walks nested
  source directories, emits deterministic output, rejects symlinks and invalid
  names, and checks the volume size before writing an image.
- [x] Implement a v2 reader with bounded, cycle-safe directory traversal and
  strict validation of every referenced block and metadata record.
- [x] Extend the VFS driver contract from root-only directory slots to
  `Stat(path)`, `Open(path)`, and `ReadDirectory(path)` for any directory. Make
  file and directory kinds explicit; opening a directory as a regular file
  should return a defined error.
- [ ] Preserve mount-generation checks so removal or remount invalidates old
  handles, including directory handles.
- [ ] Add positive tests for nested paths, empty directories and files, large
  files, both mounted volumes, and boundary-length names and paths.
- [ ] Add negative tests for duplicate names, cycles, bad parent links,
  overlapping or out-of-range extents, invalid flags, wrong checksums, and
  truncated or failed block reads.
- [x] Build `/System`, `/Bin`, `/Applications`, `/Users`, `/Volumes`, and
  `/Temporary` in the v2 image, then boot and traverse it on AHCI and NVMe.
  Preserve a v1 recovery image and exercise a corrupt-v2 fallback.

**Exit check:** the kernel lists and reads nested content on both storage
paths; damaged metadata is rejected and the recovery shell remains usable.

## Milestone 3: application-facing file inspection

- [ ] Expose versioned `stat` and directory-enumeration calls to AUEX programs
  with explicit results for success, end of directory, missing path, bad
  argument, corruption, and I/O failure.
- [ ] Deliver command arguments and dynamic paths to programs. Add bounded
  byte buffers and access to read bytes so an inspector can parse a header.
- [ ] Provide a shared, small file API for `Open`, `Read`, `Close`, `Stat`, and
  `ReadDirectory`. Ensure every path is checked against user memory limits.
- [ ] Add AUEX header parsing in userland for format version, entry point,
  code/data sizes, and stored checksums. Keep application-format knowledge out
  of generic HyFS metadata.
- [ ] Make the file inspector show unavailable fields honestly. Display file
  dates only if the filesystem has valid timestamps; report the AUEX target
  as bytecode rather than claiming a native CPU architecture.

**Exit check:** a user-built inspector accepts a path and reports a nested
file's filesystem metadata and recognized header fields without kernel-only
access.

## Milestone 4: writable block devices and a writable test volume

- [x] Add bounded `Write` to `IBlockTransport` and `BlockDevice`, with the same
  range and buffer checks used by `Read`. Define whether a failed write may
  have changed media; callers must not assume all-or-nothing physical writes.
- [x] Implement write and real cache-flush commands for AHCI and NVMe. Their
  command encoding and controller paths pass host and live tests.
- [ ] Add write failure, timeout, reset, retry, and flush failure tests. Ensure
  media removal invalidates active handles before another write begins.
  Live write failure and AHCI flush failure cases pass. Host tests cover NVMe
  flush rejection and write/flush timeouts on both controllers. Media removal
  and complete reset/retry coverage remain.
- [x] Create a writable raw-disk test configuration with a dedicated HyFS 2
  data partition. Keep ISO and recovery boot artifacts immutable.
- [x] Extend GPT volume selection and the VFS mount namespace so the writable
  data partition has a stable mount path and cannot be confused with the boot
  or removable volume.
- [x] Decide mount policy: v1 always read-only; v2 read-only by default until
  its write and recovery checks pass; damaged or unsupported v2 mounts
  read-only or fails clearly.

**Exit check, mostly passed:** write, flush, reboot, and read back the same
blocks on AHCI and NVMe. Both live write error cases and AHCI live flush error
pass. NVMe live backend flush injection is not observable with this QEMU
configuration, and broader timeout/removal testing remains before filesystem
writes are enabled.

## Milestone 5: safe HyFS 2 updates

- [ ] Implement free-space accounting and allocation with checks against
  double allocation, leaks, reserved blocks, and volume exhaustion.
- [x] Specify a transaction protocol. A practical first option is
  copy-on-write metadata and file data with two checksummed superblock slots
  carrying generation numbers. Write new data, flush it, write new metadata,
  flush it, then publish one new root generation and flush again. Recovery
  chooses the newest fully valid generation.
- [x] Implement atomic file creation and replacement first; then append,
  truncation, deletion, `mkdir`, `rmdir`, and rename. Define exactly what each
  operation guarantees across an interrupted write.
- [x] Expose VFS and userland write calls with per-volume permissions and
  checked open modes. Keep raw block access out of ordinary applications.
- [ ] Add a checker/repair or at least a read-only consistency scanner that
  reports leaked and orphaned objects without silently rewriting them.
- [x] Test after every injected interruption point, including data write,
  metadata write, flush, and superblock publication. Remount must expose
  either the old valid state or the new valid state, never a mixed tree.
- [x] Test out-of-space behavior, hot removal, repeated create/delete cycles,
  directory growth, rename across directories, and crash recovery on the
  writable test volume.

**Exit check:** users can create, update, rename, and delete files and folders;
the volume remounts consistently after power-loss simulations and live device
failures. Only then enable general persistent writes by default.

## Suggested order

1. Close the v1 validation gaps and freeze its compatibility fixture (done).
2. Specify and ship read-only HyFS 2 directories and richer metadata.
3. Expose those read APIs to applications so an inspector can be built.
4. Bring up real block writes and flushes on a separate writable volume.
5. Add transactional HyFS 2 mutations and crash recovery.

This order gives applications useful folders and inspection before the much
larger persistent-write work is finished. It also preserves a known-good v1
recovery path throughout the transition.
