# Australis OS roadmap

This file tracks **development milestones**, not published releases or ABI numbers. The detailed implementation and exit checks are in [PLAN.md](PLAN.md), with subsystem notes in the [bootloader](src/bootloader/README.md), [kernel](src/kernel/README.md), and [system userland](src/userland/system/README.md) guides.

## Current position

The default HyFS 2 ISO boots under QEMU/OVMF with AHCI or NVMe. The freestanding kernel mounts a read-only system root, starts `System.exec` as PID 1, runs ordered readiness checks, and launches a text shell. Checked AUEX programs have arguments, environment and directory context, terminal and file APIs, bounded process scheduling, and channel IPC. A small AUN1 native child path runs in ring 3 with private user mappings and a guarded stack; faults return control to PID 1 and KMon. The current native syscall surface covers PID and exit.

These are source-tree and QEMU results. They do not establish a tagged version, physical-machine compatibility, or a stable release. Component versions and the `AUKR`, `AUEX`, `AUN1`, HyFS, and boot-information ABI versions are separate from any eventual OS release number.

## Milestone status

| Area | Working development scope | Next gate |
| --- | --- | --- |
| Boot and recovery | PE32+ loader, raw `AUKR` kernel, final UEFI handoff, selectable boot modes, KMon fallback | Broader negative paths, ACPI/configuration, supported physical machines |
| Storage and VFS | AHCI/NVMe, GPT, read-only HyFS 2 system root, optional writable `/data`, HyFS 1 compatibility | Wider reset, corruption, timeout, and physical-media matrix |
| Text userland | PID 1, manifest startup, bounded retries, external shell commands, AUEX process records | Persistent services, sessions and shutdown policy |
| IPC and capabilities | Bounded versioned AUEX channels, peer identity, read-only grants, exit cleanup | Additional capability types and shared-buffer/event interfaces |
| Native user mode | AUN1 ring-3 entry, private mappings, guarded stack, PID/exit, contained #PF/#GP | Native terminal/file/IPC calls, preemption, resource accounting |
| Graphical userland | Planned | Display service, compositor, input/window protocol, desktop and apps |

Run `make test-userland-system-boot`, `make test-userland-stage4-supervision`, `make test-userland-stage5-ipc`, and `make test-native-user-mode` for the current AHCI/NVMe checks. `make test-kernel-panic` exercises the separate debug panic path. The full target matrix is in the [Makefile](Makefile).

## Release gates

- Complete the native process and syscall contract, including terminal, file, IPC, scheduling, and lifetime accounting; retain AUEX as a compatibility format during migration.
- Expand bootloader negative tests, storage recovery, USB breadth, and physical hardware validation.
- Define users, permissions, credentials, package trust, update/recovery policy, limits, and audit records before claiming general-purpose multiuser isolation.
- Keep a supported text boot while developing optional graphical sessions.
