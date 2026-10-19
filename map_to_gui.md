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

- 🟢 Improve device discovery, resource allocation and driver lifecycles:
  bounded PCI/MMIO/DMA ownership and two xHCI root devices work with
  separate transfer state, slot routing, and removal/reconnect recovery
- 🟢 Implement bounded keyboard and boot-mouse event delivery in normal context
- 🟢 Provide a validated framebuffer mode contract: the captured GOP mode is
  immutable after handoff; userland can query checked geometry, format, depth,
  and mode flags without access to framebuffer addresses
- 🟢 Add timeouts, reset paths and failure recovery for supported controllers
- 🟢 Establish a QEMU hardware compatibility and regression test matrix

### Completion: Supported devices behave predictably and recover from errors.

AHCI, NVMe, simultaneous xHCI keyboard/storage and keyboard/mouse pairs, and
the fixed framebuffer mode contract are exercised in QEMU on both storage
paths. Dynamic display modes, drawing ownership, and the compositor belong to
Phase 7. Physical hardware validation remains a separate release requirement.
See `docs/storage-driver-stability.md`.

## Phase 7: Graphics and window management

- 🟢 Build a 2D graphics library and surface abstraction: bounded RGB surfaces,
  clipped drawing, rounded shapes, alpha composition and checked GOP presentation
- 🟢 Add a user display API and exclusive display ownership: the AUEX display
  calls require a capability-granted process and a sole lease; the fixed GOP
  mode reports mode changes as unsupported because no native mode-setting
  driver exists
- 🟢 Create a user-space display server/compositor: a persistent AUEX service
  receives two independent client submissions over channels and composes
  their windows on AHCI and NVMe QEMU boots
- 🟢 Implement isolated application windows and ownership: the live service
  assigns window IDs on process-bound channels, retains separate bounded
  client RGB cell surfaces, rejects cross-window updates, and removes windows
  on close or peer exit
- 🟢 Add input focus, hit testing, clipping and damage tracking: the live
  display service routes clicks to the top window, captures content pointer
  drags, focuses the clicked window, sends USB keys only to that client, and
  restores keyboard input to the shell on a wallpaper click. It clips cell,
  focus, and cursor damage, coalesces mouse bursts to the old and final
  cursor positions, excludes rounded corners from hit tests, and uses a
  bounded full-screen fallback. The host model also tests clipped presentation
- 🟢 Build window decoration, movement, resizing and stacking: the live
  compositor draws rounded floating windows and controls, moves titles,
  resizes from invisible edges, raises clicked windows, and handles close,
  minimize, restore, and maximize. AHCI and NVMe QEMU screenshot tests
  exercise these transitions and pointer burst recovery

The window and top-bar behavior for these steps is specified in
`docs/desktop-design.md`. Implementation status and tests are in
`docs/phase7-graphics-foundation.md`.

### Completion: Two applications can display independent windows without interfering.

## Phase 8: Software rendering and performance

- 🔴 Benchmark drawing, composition and framebuffer presentation
- 🔴 Add software backbuffer and full-frame composition
- 🟡 Implement partial redraws based on dirty rectangles
- 🔴 Implement VirtIO PCI transport and queue management
- 🔴 Implement VirtIO-GPU 2D resource management
- 🔴 Add presentation latency and dropped-frame instrumentation
- 🔴 Optimise surface copying, alpha blending and framebuffer transfers
- 🔴 Add automated frame-time and rendering correctness tests

### Completion: Australis can render and present complete frames efficiently through GOP, with predictable frame scheduling, correct partial redraws and measurable performance under representative multi-window workloads.

## Phase 9: Display infrastructure and abstraction

- 🔴 Add a display backend abstraction (GOP / native)
- 🔴 Introduce frame submission and completion notifications
- 🔴 Define display buffer formats, geometry, strides and capabilities
- 🔴 Implement validated graphics buffer allocation, lifetime and ownership
- 🔴 Prevent unprivileged processes from accessing or manipulating another process's graphics buffers
- 🔴 Define explicit buffer synchronization and release semantics
- 🔴 Support multiple presentation buffers
- 🔴 Introduce display backend initialization, shutdown and recovery
- 🟢 Preserve reliable GOP fallback

### Completion: Australis can use a hardware-independent display interface with validated buffer ownership, safe frame submission, multiple presentation buffers and reliable GOP output.

## Phase 10: Native VirtIO-GPU 2D driver

- 🔴 Implement VirtIO PCI transport and queue management
- 🔴 Implement VirtIO-GPU device discovery and feature negotiation
- 🔴 Implement VirtIO-GPU 2D resource management
- 🔴 Add display mode discovery and scanout control
- 🔴 Implement framebuffer resource transfers and flush operations
- 🔴 Enforce DMA-safe memory access and resource bounds
- 🔴 Add VirtIO-GPU reset, recovery and regression
- 🔴 Recover resources safely when a compositor or application crashes
- 🔴 Implement optional hardware cursor support with software fallback
- 🔴 Validate GOP fallback when VirtIO-GPU is absent or initialization fails

### Completion: Australis can present its existing software-rendered desktop using VirtIO-GPU 2D, independently of GOP, with safe resource handling, reliable device recovery and automated QEMU regression coverage.

## Phahse 11: GPU infrastructure and resource management

- 🔴 Define a rendering backend abstraction (software / GPU)
- 🔴 Introduce GPU command submission and synchronization
- 🔴 Implement VirtIO-GPU 3D feature negotiation and context management
- 🔴 Implement VirtIO-GPU 3D/VirGL command transport
- 🔴 Implement GPU-backed textures and rendering surfaces
- 🔴 Implement GPU resource allocation, lifetime and cleanup
- 🔴 Implement GPU memory management and resource isolation
- 🔴 Validate command buffers, resource handles and submission permissions
- 🔴 Implement GPU fences, completion tracking and timeout recovery
- 🔴 Handle GPU context termination and device reset safely
- 🔴 Preserve software rendering when hardware acceleration is unavailable

### Completion: Australis can safely create, manage and release GPU-backed resources and submit supported accelerated rendering commands through VirtIO-GPU 3D/VirGL, without allowing applications to bypass resource isolation.

## Phase 12: Hardware-accelerated window composition

- 🔴 Implement accelerated window composition and alpha blending
- 🔴 Add GPU texture upload and surface update mechanisms
- 🔴 Implement GPU-backed window surfaces with software fallback
- 🔴 Accelerate window movement, resizing and stacking
- 🔴 Support GPU-accelerated clipping and rounded window regions
- 🔴 Implement GPU-accelerated shapes and transformations
- 🔴 Introduce efficient CPU-to-GPU surface synchronization
- 🔴 Implement incremental updates for damaged GPU-backed surfaces
- 🔴 Prevent applications from reading or modifying other applications' GPU resources
- 🔴 Compare GPU and CPU compositor output for rendering correctness
- 🔴 Benchmark accelerated composition against the software compositor

### Completion: Australis can compose independent application windows using GPU acceleration, including transparency, clipping and transformations, while preserving window isolation and functional software-rendering fallback.

## Phase 13: Graphics performance, synchronization and effects

- 🔴 Implement advanced frame pacing and presentation scheduling
- 🔴 Add VSync support where supported by the display backend
- 🔴 Implement presentation timing and missed-frame detection
- 🔴 Reduce CPU/GPU synchronization stalls
- 🔴 Implement efficient GPU buffer reuse and resource caching
- 🔴 Add GPU-accelerated window animations and transitions
- 🔴 Implement animated minimize, maximize and window movement effects
- 🔴 Add optional shadows, opacity and visual effects
- 🔴 Optimise rendering for high-resolution displays
- 🔴 Support configurable graphics quality and animation settings
- 🔴 Add performance monitoring for CPU rendering, GPU rendering and presentation
- 🔴 Validate smoothness, input responsiveness and frame consistency under sustained workloads

### Completion: Australis delivers consistently paced, responsive window rendering at a measured target of 60 FPS on defined reference hardware and QEMU configurations, with graceful degradation under load and reliable software fallback.

## Phase 14: Desktop and applications

- 🔴 Implement a graphical login/session manager
- 🔴 Build desktop shell, top bar, launcher and basic settings
- 🔴 Create a terminal application using the new APIs
- 🔴 Add a file manager, text editor and basic utilities
- 🔴 Define application lifecycle, packaging and permissions UX

### Completion: A user can log in, launch programs, work with files and log out.

## Phase 15: Security hardening

- 🔴 Define trust boundaries and threat models for the OS
- 🔴 Implement privilege separation and least-privilege service accounts
- 🔴 Add secure randomness and cryptographic primitives
- 🔴 Design verified boot, signed packages and trusted updates
- 🔴 Audit parsers, permissions, IPC and memory-safety boundaries

### Completion: Untrusted programs cannot gain unrestricted system access through intended APIs.

## Phase 16: Release engineering

- 🔴 Build automated CI for compiler, kernel, drivers and apps
- 🔴 Add fuzzing, stress tests and fault injection
- 🔴 Create installation, recovery and rollback mechanisms
- 🔴 Run prolonged stability tests on QEMU and real hardware
- 🔴 Publish release criteria, supported hardware and security policy

### Completion: A release candidate passes defined security, data-integrity and stability tests.
