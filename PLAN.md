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
the optional `rescue.exec`. Normal boot enters the userland `australis>` shell
through `System.exec`. The explicit `R` boot selection enters `rescue>`
without mounting a root; `D` enters KMon after hardware startup. A missing
or failed PID 1 falls back to `kmon>`.

## Current baseline

| Area | What exists | What is still missing |
| --- | --- | --- |
| Bootloader | Stage 1 handoff and AHCI/NVMe QEMU boot pass; explicit `R` Rescue works from an EFI-only disk. | Negative image/handoff tests, automated `D`/`N`/`S` mode checks, physical firmware coverage. |
| Kernel | Freestanding kernel, COM1/framebuffer console, KMon recovery controls, drivers, VFS, checked AUEX execution, bounded process records, live AUEX instruction-round scheduling, and AUN1 ring-3 children with bounded memory. | Native syscall parity, interrupt preemption, and process-wide resource accounting. |
| Storage | HyFS 2 directories, read-only boot root, transactional writes on separate `/data`, packaged `/System/Core` executables, and KMon fallback for damaged root or PID 1. | Removable-media flush and physical-device coverage. |
| Userland | Stage 1 inputs, Essentials commands, child context, launch errors, editable `PATH`, terminal parity, and read-only command cleanup pass hosted and AHCI/NVMe checks. | Precise release after filesystem mutation and broader process APIs. |
| System | PID 1 reads the versioned startup manifest, starts Device and Storage checks before the shell, waits for readiness, and bounds retries per record. | Persistent service control, dependency graphs beyond manifest order, and session supervision. |
| Rescue | `R` enters a kernel monitor without HyFS; missing or failed PID 1 falls back to KMon. | Optional `rescue.exec` and broader fault recovery coverage. |
| Shell | The userland shell parses quoted input, owns `cd`/`pwd`/history, editable `PATH`, `set`/`export`/`unset`, and launches foreground executables with context. | Background jobs require Stage 4 process support. |

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

- 🟢 Review and integrate the pending Stage 1 edits in the OS, kernel,
  userland, and Hylang compiler repositories; record the matching submodule
  revisions. Build a normal ISO separately from the Stage 1 fixture ISO.
- 🟢 Re-run `make test-userland-stage1`, the existing HyFS 2 host/write and
  AHCI/NVMe persistence checks, and a normal serial boot on both controllers.
  Record failures before adding features.
- 🟢 Maintain the system contract at `src/userland/system/README.md`;
  document the rescue contract and use `System.exec`, `CommandShell.exec`,
  `kmon>`, and `rescue>` consistently.
- 🟢 Define the exact KMon entry, PID 1 failure fallback, and normal versus
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
The later `cat.exec` slice advanced userland to `652bd84` without changing the
Stage 1 runtime.

### KMon recovery commands, 2026-10-13

The [kernel command audit](src/kernel/README.md) retains 22 required commands
and records 14 excess standalone commands for removal. `continue`, `reboot`,
`halt`, `trace`, `panic`, and `registers` now run in KMon. Early `R` Rescue
`continue` resets into a fresh normal boot because that route skips controller
and storage bootstrap; `panic` requires `D` Debug boot. The old `panic-test`
alias was removed. The compiler gained freestanding interrupt-disable and
live-register intrinsics used by these commands.

`make build`, `make test-kmon-recovery`, `make test-kernel-panic`,
`make test-rescue-boot`, and the AHCI/NVMe HyFS 2 serial console tests passed
with the source-built image. The compiler rebuilt itself to an identical
binary. Matching revisions are kernel `7f2d00e`, rescue `6ff01c7`, and Hylang
compiler `bc4914e`. Hardware reset behavior still needs physical-machine
validation.

## Stage 2 — external commands and a userland shell

- 🟢 Checked terminal, file, metadata, directory, and foreground process
  operations support the Essentials commands, child environment and
  working-directory inheritance, terminal end-of-input, and distinct
  process-launch results.
- 🟢 Build `cat.exec` from a separate userland project, install it under
  `/System/Bin`, and launch it through the existing `PATH` bootstrap with
  `run cat /path`. `make test-userland-cat` passed on AHCI and NVMe.
- 🟢 Build and install `ls.exec`, `version.exec`, and `echo.exec` under
  `/System/Bin`. `pwd` is a shell built-in because it reads shell-owned directory
  state.
- 🟢 Implement foreground command launch, argument passing, quoted input,
  `cd`, `pwd`, `history`, `help`, `exit`, and explicit `run` in
  `CommandShell.exec`; KMon remains the recovery fallback.
- 🟢 Add session-local `PATH` lookup with the `path` built-in.
- 🟢 Add environment built-ins (`set`, `export`, `unset`) and child
  environment propagation.
- 🟢 Unknown commands, faults, and nonzero exits return to the prompt.
  Missing-image, invalid-image, permission, and terminal EOF results have
  distinct user-facing handling.
- 🟢 COM1, USB, serial, and framebuffer behavior pass the Stage 2 boot test.
  Repeated read-only and missing-image launches keep allocator, descriptor,
  mapping, and input-queue counters stable.

**Exit:** `cat /hello.txt`, `ls /`, and `version` resolve via `PATH`
as external programs over COM1 and USB keyboard; serial and framebuffer
output agree; repeated read-only and failed launches leave descriptor, page,
mapping, and queue counts stable. The shell survives a bad executable.

`make test-userland-essentials` boots both AHCI and NVMe, runs shell
built-ins and external file commands, copies a multi-chunk file, mutates a
disposable `/data` volume, and returns to KMon after `exit`.
`make test-userland-shell-preview` verifies the compiled shell's argument
handoff in the hosted runtime. `make test-userland-stage2` covers child
context, launch errors, EOF, and COM1/USB plus serial/framebuffer parity.
The Stage 2 exit checks pass on AHCI and NVMe. The shell's command boundary
reclaims managed pages for read-only and failed launches; filesystem mutation
commands keep pages that may be referenced by persistent HyFS 2 metadata.
Precise ownership and release for those retained pages remains later kernel
memory work.

## Stage 3 — complete the system image and recovery path

- 🟢 Make the HyFS 2 image builder package OS-owned commands, libraries, and
  system components at the paths in `src/README.md`. Do not use a dummy
  `System.exec` to claim PID 1 works.
- 🟢 Verify the required `/System`, `/System/Bin`, `/Applications`, `/Users`,
  `/Volumes`, and `/Temporary` hierarchy on AHCI and NVMe. Keep HyFS 1
  compatibility separate from this boot contract.
- 🟢 Add boot tests for missing, malformed, and corrupt system executables
  and root metadata. Define how KMon enters before or after a failed normal
  boot. If `rescue.exec` is supplied, make its relationship to KMon explicit.

**Exit:** the kernel mounts and traverses the packaged root on both
controllers, rejects corrupt metadata or an invalid system image, and offers
KMon with no dependency on PID 1 or writable storage.

`make test-userland-stage3` booted disposable images on AHCI and NVMe and
reached a working `kmon>` after removal of `System.exec`, replacement with a
malformed payload, and corruption of both HyFS 2 superblocks. The normal
image packer verifies the required system paths and AUEX headers before
publishing the ISO.

## Stage 4 — PID 1 and supervised text startup

- 🟢 Keep bounded kernel process records with PID, parent PID, running,
  waiting, exit/fault status, and instruction counts. Live AUEX children can
  spawn independently, wait, report readiness, terminate, and sleep under
  bounded instruction-round scheduling with separate descriptor owners.
- 🟡 Timer-backed sleep and instruction quanta provide cooperative scheduling
  for AUEX programs. Interrupt preemption and native context switching remain.
- 🟢 Build and install `/System/Core/System.exec`; start it as PID 1 after
  mounting the root. It launches `CommandShell.exec` for a text session.
- 🟡 Package an `AUSM1` startup manifest. PID 1 starts one-shot Device and
  Storage readiness checks, then CommandShell, in declared order. Each record
  has a bounded readiness wait and retry limit; failures are logged and PID 1
  returns to KMon when exhausted. Persistent services, dependency graphs,
  graceful shutdown, and Launch policy remain.
- 🟢 Bound `CommandShell.exec` restarts in PID 1 to three failed launches,
  emit attempt and status records, and stop on a normal shell exit.
- 🟢 Provide an explicit boot bypass into KMon and a fallback when PID 1
  cannot be loaded. Bounded repeated-failure handling remains open.

**Exit:** PID 1 starts the shell, restarts one deliberately failing service
only up to its limit, records why it stopped, and leaves KMon usable. No
service executes in an interrupt handler or retains resources after exit.

`make test-userland-stage4-supervision` replaces the shell with a valid
faulting AUEX image on disposable AHCI and NVMe boot volumes. It verifies
three attempts, the limit record, and an interactive KMon fallback.

## Stage 5 — IPC and capabilities

- 🟢 Add a kernel-owned, bounded versioned channel primitive with PID-owned
  endpoints, copied messages, stale-handle rejection, and close-on-process-exit
  cleanup.
- 🟡 Expose checked AUEX channel open, accept, send, receive, wait, peer, and
  close calls. Shared buffers and general event waits remain.
- 🟡 Authenticate channel peers by process identity and grant channel creation
  only to paths listed in the read-only `AUSC1` capability manifest. Device,
  mount, process inspection, display, input, and service grants remain.

**Exit:** an unprivileged program can use its terminal and allowed files but
cannot control mounts, inspect protected processes, or map the framebuffer;
closing either endpoint releases queued messages and pages.

The hosted channel tests cover peer PID checks, protocol version, queue bounds,
payload copying, close cleanup, and stale handles. The AHCI/NVMe IPC image
test checks an allowed exchange, denied open, and exit cleanup.

## Stage 6 — sessions and optional graphical userland

- 🔴 Add login and per-session environment, directory, terminal, and process
  ownership. Keep a supported text-only boot. At this stage `Login.exec` may
  start a session; it must not claim to enforce authentication until Stage 7
  supplies protected credentials, access control, and process isolation.
- 🔴 Build Display service, compositor, window/input protocol, DesktopShell,
  Terminal, and Explorer on the public service contracts.

**Exit:** a graphical session launches an external command and recovers from
a faulty client while COM1 remains an independent recovery console.

## Stage 7 — native user mode and release hardening

- 🟢 Run AUN1 children with bounded memory from the read-only system volume in ring 3,
  with supervisor-only copied kernel mappings, owned code/data/stack pages,
  an unmapped stack guard, TSS entry, `int 0x80` PID/exit, and contained
  page and general-protection faults. Record native exit/fault state in the
  shared process table. AHCI and NVMe checks preserve PID 1 and KMon.
- 🟡 Move the remaining terminal, file, IPC, and scheduling contracts into
  native syscalls; add native interrupt preemption and resource accounting.
  Keep AUEX as a compatibility format during migration.
- 🔴 Complete bootloader negative tests, ACPI/configuration and selectable
  diagnostics as required for release; test cold boot, restart, and failure
  paths on physical supported machines.
- 🔴 Add users, groups, permissions, protected credential verification,
  package trust, update/recovery policy, resource limits, and audit records.

**Exit:** a native process cannot access kernel pages or privileges, and its
fault returns resources without taking down PID 1 or recovery. Supported
physical machines pass the boot and storage failure matrix.

## Immediate next work

Gate 0, Stage 2, and the Stage 3 image and recovery path pass their stated
exit checks. Stage 4 now has live AUEX children and ordered manifest startup.
The native ring-3 entry and fault-containment path now passes QEMU boot checks.
Next, extend the native syscall surface, persistent service control, and
precise lifetime handling for pages retained by filesystem writes.
