# Australis userland plan

This directory is the planned home of operating-system programs that execute
above the kernel. The GUI is one userland subsystem. Command-line tools,
services, login, sessions, and the desktop all use the same process boundary.

The current kernel shell remains the recovery console until the userland shell
can boot, launch commands, and survive failed programs on both storage paths.

## Boundary with the kernel

The kernel should expose small, versioned mechanisms:

- process creation, arguments, waiting, termination, and scheduling;
- user memory, descriptors, system calls, and fault containment;
- files, directories, mounts, devices, clocks, and system information;
- IPC endpoints, events, capabilities, and shared buffers;
- framebuffer, input, storage, and network driver interfaces.

Userland should implement policy:

- system and service startup order;
- service restart and failure reporting;
- environment variables and executable search;
- mount, device, network, login, and session policy;
- application manifests and capability requests;
- display composition, windows, desktop behavior, and notifications.

## Stage 1: process inputs and application runtime

### Kernel and AUEX

- Define a versioned process-start record containing `argc`, `argv`,
  environment entries, working directory, and standard descriptors.
- Copy all start data through checked user memory and reject malformed counts,
  lengths, pointers, and duplicate ownership.
- Add syscall results with explicit success, end-of-file, retry, invalid
  argument, not found, permission, and I/O error states.
- Add dynamic-path open calls and read-only system-information queries.
- Add process identifiers plus foreground `spawn`, `wait`, and exit status.

### Compiler

- Populate `Main(string[] args)` for `type = "exec"` projects.
- Add locals, integer and Boolean operations, comparisons, branches, loops,
  and method calls to the AUEX backend.
- Add bounded strings and byte arrays backed by the user data region.
- Preserve the existing AUEX validation, CRC, instruction limit, and cleanup
  behavior.

### Exit test

An argument-printing `.exec` receives multiple edited arguments, returns a
nonzero status, and leaves descriptor and page counts unchanged after repeated
AHCI and NVMe QEMU runs.

## Stage 2: external command shell

- Move `cat`, `version`, `echo`, and `pwd` into independent `type = "exec"`
  projects.
- Add user-facing directory enumeration and metadata, then move `ls` out of
  the kernel shell.
- Implement shell variables and `PATH` lookup. Start with
  `PATH=/Bin:/System/Bin` once filesystem directories exist.
- Keep `cd`, `set`, `export`, `unset`, and `exit` as shell built-ins.
- Retain explicit `run /path/program.exec` during the transition.
- Return command-not-found, invalid executable, signal/fault, and exit-status
  information without losing the interactive terminal.

### Exit test

`cat /hello.txt`, `ls /`, and `version` resolve through `PATH` as external
programs over COM1 and USB keyboard input. Their output is identical on the
serial and framebuffer terminals. Repeated execution has no page, descriptor,
mapping, queue, or partial-output leak.

## Stage 3: directory-capable system image

- Define a directory-capable HyFS revision with stable identifiers, checked
  metadata, file lengths, directory entries, and CRC coverage.
- Add atomic creation and replacement primitives before enabling general
  writes. Add flush semantics before removable-media writes.
- Create `/System`, `/Bin`, `/Applications`, `/Users`, `/Volumes`, and
  `/Temporary`.
- Package system components and applications into the paths documented in
  `src/system/README.md`.
- Preserve read-only mounting and recovery when a volume is damaged or removed.

### Exit test

The kernel mounts the directory-capable root on AHCI and NVMe, traverses the
system hierarchy, rejects corrupted metadata, and continues to expose the
recovery shell when the userland image is missing or invalid.

## Stage 4: system manager and services

- Replace the placeholder `SYSTEM.EFI` with `/System/Core/System.exec`.
- Start it as PID 1 after the kernel mounts the root filesystem.
- Add a process table with parent, child, running, blocked, exited, and faulted
  states.
- Support multiple runnable processes, blocking waits, timers, and preemption.
- Define service manifests, dependency ordering, readiness, restart limits,
  shutdown, and structured failure records.
- Introduce `Device.service`, `Storage.service`, and `Launch.service` as policy
  services over kernel APIs.
- Keep a kernel recovery key or boot option that bypasses normal userland.

### Exit test

PID 1 starts the command shell, restarts one deliberately failed service up to
its declared limit, records the cause, and keeps the recovery console usable.
No service executes in an interrupt handler or retains resources after exit.

## Stage 5: IPC and capabilities

- Add bounded message channels, event waiting, process handles, and shared
  buffers with explicit ownership.
- Authenticate peers by kernel process identity rather than filenames.
- Grant capabilities for devices, mounts, process inspection, system settings,
  display ownership, input routing, and service control.
- Make application manifests request capabilities; the launcher supplies only
  the approved subset.
- Version every public service protocol and reject incompatible messages.

### Exit test

An unprivileged application can use terminal and file services but cannot
control mounts, enumerate protected processes, or map the framebuffer. Closing
either endpoint releases queued messages and shared pages.

## Stage 6: sessions and graphical userland

- Add `Login.exec` and a session manager with per-session environment,
  working directory, terminal, and process ownership.
- Give `Display.service` exclusive display and routed-input capabilities.
- Implement a compositor, window protocol, surfaces, damage tracking, pointer
  events, focus, and keyboard routing in userland.
- Build `DesktopShell.appb`, then `Terminal.appb` and `Explorer.appb` against
  the public display and launch protocols.
- Keep text-only startup as a supported configuration.

### Exit test

A graphical session starts after login, opens a terminal, launches an external
command, and recovers when a client submits an invalid surface or exits during
input delivery. COM1 continues to provide an independent recovery console.

## Stage 7: native user mode and hardening

- Add ring-3 execution, per-process page tables, user/supervisor permissions,
  guarded user stacks, syscall entry/return, and user exception delivery.
- Port the established AUEX process and syscall contracts to native code while
  retaining AUEX as a deterministic compatibility format if useful.
- Add users, groups, permissions, signed system packages, secure update and
  recovery policy, resource limits, and audit records.
- Validate on physical machines in addition to the QEMU matrix.

### Exit test

Native user code cannot read or write kernel pages, cannot invoke privileged
instructions, and cannot impersonate a service. A process fault terminates only
that process and returns its resources while PID 1 and both recovery terminals
remain operational.

## First implementation slice

The next code change should stay smaller than the complete plan:

1. define the process-start and syscall-result records;
2. pass literal shell arguments into an AUEX process;
3. expose one argument at a time through checked user memory;
4. add dynamic read-only file open by argument;
5. compile `cat.exec` as the first external command;
6. retain the built-in `cat` as recovery fallback until the QEMU matrix passes.

That slice establishes the ABI needed by later services without committing the
kernel to the GUI, package, or native-process design prematurely.
