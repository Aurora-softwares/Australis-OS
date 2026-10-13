# Australis OS active plan

Reviewed 2026-10-13. This file is the implementation order and set of exit
gates for the current OS. The earlier bootstrap checklist in this file is
retained in Git history; completed bootstrap work is summarized here rather
than treated as the next milestone.

## Intended boot path and ownership

```text
BOOTX64.EFI -> KERNEL.BIN -> /System/Core/System.exec (PID 1)
                                      -> CommandShell.exec (text session)
                                      -> optional graphical session
```

The bootloader validates and starts the kernel. The kernel owns hardware,
memory, scheduling, process isolation, system calls, and VFS. System userland
owns startup, services, mounts, sessions, and launch policy. The userland shell
owns command parsing, environment, `PATH`, and foreground jobs. Applications
use public APIs. A kernel monitor (KMon) must remain reachable when the root
volume or PID 1 cannot start. A future `rescue.exec` may add tools when a
valid volume is available; it cannot be the only recovery route.

Follow [the architecture](src/README.md) for these boundaries and package
names, [the userland stages](src/userland/README.md) for feature order, and the
[bootloader](src/bootloader/README.md) and [kernel](src/kernel/README.md)
READMEs for their completion criteria. The architecture uses `System.exec`
and `CommandShell.exec`; the system contract is at
[src/userland/system/README.md](src/userland/system/README.md). The
[rescue README](src/rescue/README.md) distinguishes the kernel monitor from
the optional `rescue.exec`. The current normal monitor prompt is `kmon>`;
the explicit `R` boot selection enters `rescue>` without mounting a root.
Automatic fallback from a failed normal boot or PID 1 remains future work.

## Current baseline

| Area | What exists | What is still missing |
| --- | --- | --- |
| Bootloader | Stage 1 handoff and AHCI/NVMe QEMU boot pass; explicit `R` Rescue works from an EFI-only disk. | Negative image/handoff tests, automated `D`/`N`/`S` mode checks, physical firmware coverage. |
| Kernel | Freestanding kernel, COM1/framebuffer console, drivers, VFS, and checked AUEX execution. | Native ring 3, independent runnable processes, preemption, and the general process table needed by PID 1. |
| Storage | HyFS 2 directories, read-only boot root, transactional writes on separate `/data`, and recovery tests are documented. | A packaged system manager and a tested missing/corrupt userland fallback. |
| Userland | Stage 1 process input/runtime work passes hosted and AHCI/NVMe QEMU tests from source. | Stage 2 external command set and a userland command shell. |
| System | The architecture, system contract README, and `/System/Core` directory exist. | `System.exec`, PID 1 launch, and services. The current image has an empty `/System/Core`. |
| Rescue | `R` enters a kernel monitor without HyFS; an EFI-only QEMU boot passes. | Automatic normal-boot and PID 1 failure fallback, optional `rescue.exec`. |
| Shell | The recovery shell already parses arguments and searches `PATH`. | Userland shell implementation; `src/shell/program.hy` is empty. |

The baseline checks below distinguish the Stage 1 fixture image from the
normal image. Unrelated local edits in application README files are outside
this source baseline.

## Execution rules

1. Work on one numbered stage at a time. A working API or directory layout is
   a dependency, not completion of the stage that uses it.
2. Each stage ends with a source-built artifact, hosted failure tests, and
   AHCI/NVMe QEMU checks. Keep COM1 recovery usable after faults.
3. Put OS commands and policy in userland. Keep kernel built-ins only for KMon
   and recovery while replacements are proved.
4. Keep the boot root read-only and use disposable `/data` images for write
   tests. Do not require a writable root for startup or recovery.
5. Update the relevant README and this plan when a gate passes. Do not infer
   completion from a checklist mark alone; record the command and observed
   result.

## Gate 0 — reconcile and freeze the baseline

- [x] Review and integrate the pending Stage 1 edits in the OS, kernel,
  userland, and Hylang compiler repositories; record the matching submodule
  revisions. Build a normal ISO separately from the Stage 1 fixture ISO.
- [x] Re-run `make test-userland-stage1`, the existing HyFS 2 host/write and
  AHCI/NVMe persistence checks, and a normal serial boot on both controllers.
  Record failures before adding features.
- [x] Maintain the system contract at `src/userland/system/README.md`;
  document the rescue contract and use `System.exec`, `CommandShell.exec`,
  `kmon>`, and `rescue>` consistently.
- [x] Define the exact KMon entry, PID 1 failure fallback, and normal versus
  debugging boot behavior. Recovery must not depend on HyFS or AUEX.

**Exit:** clean, reproducible build; one documented name and owner for each
boot component; baseline tests pass; a failure can still reach KMon.

### Gate 0 verification, 2026-10-13

All commands below passed in the OS checkout:

- `make build` and `make BUILD_DIR=/tmp/australis-gate0-clean-20261013 iso`:
  source-built EFI loader, raw kernel, applications, and HyFS 2 ISO from an
  empty output directory.
- `make test-userland-stage1`: hosted runtime plus AHCI and NVMe QEMU boots.
- `make test-hyfs2`: HyFS 2 host image and writer checks, including the HyFS 1
  compatibility fixture.
- `make test-stage6-ahci test-stage6-nvme`: persistent writes, reboot, and
  removal on both controllers using disposable data images.
- `make iso`, then `make test-hyfs2-serial-ahci test-hyfs2-serial-nvme`:
  normal image without Stage 1 or persistence fixtures; both interactive
  serial boots passed.
- `make test-rescue-boot`: `R` reached `rescue>` and ran `help` from a FAT-only
  EFI disk with no HyFS partition.

Matching source revisions: bootloader `188ec49`, kernel `40bcb55`, userland
`b8eea3e`, shell `5aed63a`, rescue `fb99930`, and Hylang compiler `41f5179`.
The OS repository records these submodule revisions. The application README
checkouts contain unrelated local edits; they did not affect these builds.

## Stage 2 — external commands and a userland shell

- [ ] Expose the remaining application-facing environment, working-directory,
  terminal, file, metadata, directory, and process-launch/wait operations
  needed by ordinary commands. Keep results versioned and checked.
- [ ] Build `cat.exec`, `ls.exec`, `version.exec`, `echo.exec`, and
  `pwd.exec` from separate userland projects and install them under `/Bin`.
  Use the existing HyFS 2 tree and `PATH` bootstrap.
- [ ] Implement `CommandShell.exec` in userland. Keep `cd`, `set`,
  `export`, `unset`, and `exit` as its built-ins. Keep explicit
  `run /path/program.exec` and the current kernel commands as recovery
  fallbacks until the new shell passes.
- [ ] Add failure handling for unknown commands, invalid images, program
  faults, EOF, and nonzero exits without losing the interactive terminal.

**Exit:** `cat /hello.txt`, `ls /`, and `version` resolve via `PATH`
as external programs over COM1 and USB keyboard; serial and framebuffer
output agree; repeated runs leave descriptor, page, mapping, and queue counts
stable. The shell survives a bad executable.

## Stage 3 — complete the system image and recovery path

- [ ] Make the HyFS 2 image builder package OS-owned commands, libraries, and
  system components at the paths in `src/README.md`. Do not use a dummy
  `System.exec` to claim PID 1 works.
- [ ] Verify the required `/System`, `/Bin`, `/Applications`, `/Users`,
  `/Volumes`, and `/Temporary` hierarchy on AHCI and NVMe. Keep HyFS 1
  compatibility separate from this boot contract.
- [ ] Add boot tests for missing, malformed, and corrupt system executables
  and root metadata. Define how KMon enters before or after a failed normal
  boot. If `rescue.exec` is supplied, make its relationship to KMon explicit.

**Exit:** the kernel mounts and traverses the packaged root on both
controllers, rejects corrupt metadata or an invalid system image, and offers
KMon with no dependency on PID 1 or writable storage.

## Stage 4 — PID 1 and supervised text startup

- [ ] Add a real process table with identity, parent/child state, exit/fault
  records, blocking waits, timers, and multiple runnable AUEX processes.
  Establish the scheduling behavior required by services before adding them.
- [ ] Build and install `/System/Core/System.exec`; start it as PID 1 after
  mounting the root. It launches `CommandShell.exec` for a text session.
- [ ] Add versioned service manifests and bounded readiness, restart,
  shutdown, and structured failure behavior. Start with Device, Storage, and
  Launch policy; retain drivers and mechanism in the kernel.
- [ ] Provide an explicit boot bypass into KMon and a fallback when PID 1
  cannot be loaded or repeatedly fails.

**Exit:** PID 1 starts the shell, restarts one deliberately failing service
only up to its limit, records why it stopped, and leaves KMon usable. No
service executes in an interrupt handler or retains resources after exit.

## Stage 5 — IPC and capabilities

- [ ] Add bounded, versioned channels, events, process handles, and shared
  buffers with explicit ownership and cleanup.
- [ ] Authenticate peers by process identity and grant only declared
  capabilities for devices, mounts, process inspection, display, input, and
  service control.

**Exit:** an unprivileged program can use its terminal and allowed files but
cannot control mounts, inspect protected processes, or map the framebuffer;
closing either endpoint releases queued messages and pages.

## Stage 6 — sessions and optional graphical userland

- [ ] Add login and per-session environment, directory, terminal, and process
  ownership. Keep a supported text-only boot.
- [ ] Build Display service, compositor, window/input protocol, DesktopShell,
  Terminal, and Explorer on the public service contracts.

**Exit:** a graphical session launches an external command and recovers from
a faulty client while COM1 remains an independent recovery console.

## Stage 7 — native user mode and release hardening

- [ ] Port the established process/syscall contracts to ring 3 with
  per-process page tables, guarded stacks, user exception delivery, and
  hardware-enforced privilege separation. Keep AUEX as a compatibility format
  if useful.
- [ ] Complete bootloader negative tests, ACPI/configuration and selectable
  diagnostics as required for release; test cold boot, restart, and failure
  paths on physical supported machines.
- [ ] Add users, groups, permissions, package trust, update/recovery policy,
  resource limits, and audit records.

**Exit:** a native process cannot access kernel pages or privileges, and its
fault returns resources without taking down PID 1 or recovery. Supported
physical machines pass the boot and storage failure matrix.

## Immediate next work

Finish Gate 0 first. Then implement the smallest Stage 2 vertical slice:
a source-built `cat.exec` using a dynamic path and explicit EOF/error results,
installed in `/Bin`, launched through `PATH`, and tested on both storage
paths. Add `ls`, `version`, `echo`, and `pwd` only after that slice passes.
