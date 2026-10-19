# Storage safety and hardware regression matrix

This page records the supported Phase 5 and 6 profile. The test machine is
QEMU `q35` with OVMF, 256 MiB RAM, and either an emulated AHCI disk or NVMe
namespace. Physical hardware is not yet qualified.

## Storage contract

The boot HyFS volume and removable USB HyFS volume are read-only. A separate
GPT data partition mounts as writable HyFS 2 at `/data`; a missing or invalid
data partition does not turn the boot root writable. VFS handles record their
mount generation and reject use after removal or remount. AUEX and AUN1 file
access is checked for open mode, path, and process-owned handles. Native AUN1
file calls use bounded copies and the same VFS read-only policy.

HyFS 2 mutations use copy-on-write data and metadata. The writer flushes new
data, flushes new metadata, publishes an inactive checksummed superblock with
a higher generation, then flushes that publication. Remount selects the newest
fully valid generation. A failed write is never assumed to leave the medium
unchanged; controller code does not blindly retry writes. The independent
`tools/hyfs2.py check IMAGE` command inspects superblocks, parent links,
extents, and unreferenced nonzero blocks without modifying the image.

Host tests inject interruption during data write, metadata write, flush, and
superblock publication, then remount to require the old or new complete tree.
Live disposable-disk tests write and flush on AHCI and NVMe, reboot, and read
back the data. Both reject injected writes. AHCI also rejects an injected
backend flush; QEMU's NVMe backend does not forward that blkdebug flush fault,
so NVMe flush rejection is verified with the host controller mock.
`make test-native-files` also exercises AUN1 file handles on both controllers,
then scans the data volume after reboot.

## Device ownership and display mode

The kernel scans PCI for supported storage and xHCI functions, validates BARs,
maps bounded MMIO, and allocates DMA from a reserved pool. The xHCI owner has
one controller and supports two simultaneous root-port devices when the
controller exposes two slots and the reserved DMA pool can accommodate both.
Each device has separate contexts, rings, queues, and transfer state. Events
are routed by slot or port; removal and reconnect trigger bounded controller
recovery and re-enumeration. Keyboard and mouse transfer completions are
decoded in normal kernel context after IRQ acknowledgement.
The mouse queue holds 63 complete events, rejects invalid values, reports
overflow, and clears stale events on disconnect. A consumer can poll button
state and signed X/Y deltas through `NativeXhci.PollMouseEvent`.

The framebuffer interface describes the single GOP mode captured before
`ExitBootServices`: base, byte length, width, height, stride, and 32-bit RGB or
BGR pixel format. `FramebufferMode` rejects malformed geometry, unaligned or
wrapping ranges, and out-of-bounds pixel coordinates. The text terminal uses
that validated mode. System-information API 5 exposes read-only width, height,
stride, format, 32-bit depth, and valid/fixed flags to AUEX user programs;
it never exposes the physical framebuffer address. The mode remains fixed
after handoff. Dynamic mode changes, drawing ownership, and the compositor
belong to Phase 7.

## Regression matrix

| Device/path | Positive check | Failure or boundary check | Command |
| --- | --- | --- | --- |
| AHCI + GPT + HyFS 2 | Mount root and persist `/data` writes | Timeout, reset, failed write and flush, corrupt image | `make test-ahci-controller test-partitions test-stage6-ahci` |
| NVMe + GPT + HyFS 2 | Mount root and persist `/data` writes | Timeout, reset, failed write; host flush rejection | `make test-nvme-controller test-partitions test-stage6-nvme` |
| USB boot keyboard | Typed shell and AUEX input on both boot disks | Key release, repeat, ring wrap, disconnect and recovery | `make test-stage3` |
| USB boot mouse | Enumerate and deliver motion on both boot disks | Queue bounds, rejected values, no shell action from IRQ, removal and reconnect | `make test-usb test-mouse` |
| USB mass storage | Read-only `/usb` mount on both boot disks | BOT failure, sense and removal | `make test-stage4` |
| Two xHCI root devices | Keyboard + storage and keyboard + mouse on both boot disks | Independent reports, removal/reconnect in both directions, stable DMA ownership | `make test-xhci-multi` |
| GOP framebuffer + COM1 | Mirrored terminal and read-only user mode query on both boot disks | Invalid geometry/ranges, serial fallback, query matches captured GOP mode | `make test-terminal test-userland-info test-serial-ahci test-serial-nvme` |
| HyFS 2 transactions | Atomic create/replace, rename, deletion, remount | Every simulated interruption point, exhaustion, scanner | `make test-hyfs2` |
| Native AUN1 files | Per-process handles and persistent `/data` writes on AHCI/NVMe | Read-only boot policy, invalid pointer, closed handle, reboot and scanner | `make test-native-files` |

Run `make test-phase5-6` for the complete serial matrix; the individual
targets are listed above for focused diagnosis. Several rebuild the same ISO.
The matrix
describes QEMU compatibility, not a guarantee for arbitrary controllers,
firmware, USB hubs, or physical power failure. Before a hardware release,
repeat persistence, removal, reset, and display checks on named physical
controllers and record firmware versions and failures here.
