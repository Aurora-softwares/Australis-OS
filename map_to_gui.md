# Roadmap to GUI

🟢 Implemented, 🟡 Partial implementation, 🔴 Absent.

## Phase 1: Kernel reliability

- 🟢 Define and document kernel invariants and ownership rules
- 🟢 Audit physical memory allocation, alignment and bounds checks
- 🟢 Implement reliable exception handling and fault classification
- 🟢 Strengthen interrupt handling, timers and locking
- 🟢 Add serial crash diagnostics and reproducible panic reports

### Completion: Kernel survives controlled faults and reports actionable diagnostics.

## Phase 2: Memory protection

- 🟢 Implement virtual memory management for the supported AUN1 address space
- 🟢 Separate kernel and user page tables with supervisor/user permissions
- 🟢 Enforce writable-versus-executable permissions on user and new kernel mappings
- 🟢 Implement guarded user stacks and safe address-space switching
- 🟢 Add page fault recovery and malicious pointer tests

### Completion: A user process cannot read or modify kernel memory.

Verified for AUN1 ring-3 children on AHCI and NVMe in QEMU. See
`docs/memory-protection.md` for the mapping contract, adversarial tests, and
the remaining kernel bootstrap mapping hardening work.

## Phase 3: Processes and scheduling

- 🟢 Define process and thread structures, states and ownership
- 🟢 Implement native ring-3 process entry and return
- 🟢 Build timer-driven context switching and preemptive scheduling
- 🟢 Add process termination, cleanup and resource limits
- 🟢 Implement safe wait, exit and parent/child lifecycle handling

### Completion: Multiple independent processes run and fail without crashing each other.

Verified for AUEX and AUN1 children on AHCI and NVMe in QEMU. The native
profile is single-CPU with one thread per process; see
`docs/process-scheduling.md` for its lifecycle and limits.

## Phase 4: System calls and IPC

- 🟢 Define a versioned syscall ABI and error conventions
- 🟢 Implement validated user/kernel data copying
- 🟢 Introduce per-process handle tables and access rights
- 🟢 Implement bounded IPC messages and synchronization
- 🟢 Add capability-based authorization and service isolation

### Completion: Applications access privileged resources only through validated interfaces.

Verified for the current AUEX and AUN1 profiles on AHCI and NVMe in QEMU.
Native applications use ABI version 1, checked copies, and invited channel
handles; AUEX file handles and channel creation are owner- and grant-checked.
See `docs/system-calls-ipc.md` for limits and error codes. Native file calls
are covered in Phase 5; native device APIs remain future work.

## Phase 5: Storage and filesystem safety

- 🟢 Harden AHCI, NVMe, USB and GPT input validation for the supported devices
- 🟢 Define VFS permissions and per-process file handles for AUEX and AUN1,
  including open modes, mount generations, and owner checks
- 🟢 Introduce a writable HyFS 2 `/data` volume with generation recovery
- 🟢 Add write ordering, real flushes, and injected power-loss tests
- 🟢 Implement atomic file replacement and read-only integrity checking

### Completion: Unexpected shutdowns do not routinely destroy stored data.

The transactional `/data` profile passes host interruption tests and live
AHCI/NVMe persistence and failure tests in QEMU. Native AUN1 file handles
also pass read-only policy and reboot persistence checks on both controllers.
Physical power-loss validation remains future hardware work. See
`docs/storage-driver-stability.md`, `docs/hyfs-v2.md`, and
`docs/system-calls-ipc.md`.

## Phase 6: Driver and hardware stability

- 🟡 Improve device discovery, resource allocation and driver lifecycles:
  bounded PCI/MMIO/DMA ownership works; xHCI still owns one root device
- 🟢 Implement bounded keyboard and boot-mouse event delivery in normal context
- 🟡 Provide a validated framebuffer mode contract: the captured GOP mode is
  immutable after handoff; mode switching and a user display API remain open
- 🟢 Add timeouts, reset paths and failure recovery for supported controllers
- 🟢 Establish a QEMU hardware compatibility and regression test matrix

### Completion: Supported devices behave predictably and recover from errors.

AHCI, NVMe, xHCI keyboard, mouse, and read-only USB storage are exercised in
QEMU on both storage paths. The one-device xHCI limit, no post-handoff display
mode switching, and untested physical hardware keep this phase open. See
`docs/storage-driver-stability.md`.

## Phase 7: Graphics and window management

- 🔴 Build a 2D graphics library and surface abstraction
- 🔴 Create a user-space display server/compositor
- 🔴 Implement isolated application windows and ownership
- 🔴 Add input focus, hit testing, clipping and damage tracking
- 🔴 Build window decoration, movement, resizing and stacking

### Completion: Two applications can display independent windows without interfering.

## Phase 8: Desktop and applications

- 🔴 Implement a graphical login/session manager
- 🔴 Build desktop shell, launcher, taskbar and basic settings
- 🔴 Create a terminal application using the new APIs
- 🔴 Add a file manager, text editor and basic utilities
- 🔴 Define application lifecycle, packaging and permissions UX

### Completion: A user can log in, launch programs, work with files and log out.

## Phase 9: Security hardening

- 🔴 Define trust boundaries and threat models for the OS
- 🔴 Implement privilege separation and least-privilege service accounts
- 🔴 Add secure randomness and cryptographic primitives
- 🔴 Design verified boot, signed packages and trusted updates
- 🔴 Audit parsers, permissions, IPC and memory-safety boundaries

### Completion: Untrusted programs cannot gain unrestricted system access through intended APIs.

## Phase 10: Release engineering

- 🔴 Build automated CI for compiler, kernel, drivers and apps
- 🔴 Add fuzzing, stress tests and fault injection
- 🔴 Create installation, recovery and rollback mechanisms
- 🔴 Run prolonged stability tests on QEMU and real hardware
- 🔴 Publish release criteria, supported hardware and security policy

### Completion: A release candidate passes defined security, data-integrity and stability tests.
