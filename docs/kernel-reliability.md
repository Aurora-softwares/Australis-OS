# Kernel reliability contract (Phase 1)

This contract applies to the current x86-64 bootstrap processor kernel. The
bootloader hands off once UEFI boot services are gone. The kernel owns the
`KernelBootInfo` record, its interrupt tables, page tables, and the published
physical allocator range from that point onward.

## Invariants and ownership

- `KernelBootInfo` must be 4 KiB aligned, have magic `AUBI` and version 7,
  and name a page-aligned allocator cursor and exclusive limit. The kernel
  validates it before using post-handoff services.
- `PhysicalPages.Initialize` records the allocator cursor at entry in the
  previously unused 64-bit field at offset 3608. Pages below that floor,
  including bootloader structures and the allocator metadata page, cannot be
  returned through `PhysicalPages.Free`. A successful allocation transfers one
  zeroed 4 KiB page to the caller. A successful free ends that ownership;
  double frees and unaligned or out-of-range pages are rejected.
- The free list has one owner: the foreground kernel on the bootstrap CPU.
  Its head, count, and links must remain within the allocated interval.
  `RewindTransient` accepts only the latest recorded marker and refuses to
  pass over a free-list node. Callers must first release every live reference
  into the rewound interval. A refused rewind leaves the cursor unchanged.
- `KernelAddressSpace.UnmapPage` relinquishes a virtual mapping and its
  private page-table pages, never the mapped physical frame. The caller frees
  a frame only after unmapping every alias it owns. MMIO mappings belong to
  their device owner and must be released before that owner is destroyed.
- IRQ stubs only capture and acknowledge device state. Foreground code owns
  managed objects, device lifecycles, and event queue consumption. The xHCI
  pending count is moved to the queue with interrupts masked and the prior IF
  state restored. Registration publishes the vector last; unregistration
  clears it first.
- The current kernel runs on one CPU and does not schedule native kernel
  threads. Short interrupt-masked sections protect data shared with IRQs.
  General spinlocks would not add safety until kernel threads or other CPUs
  are introduced; that transition must review these ownership rules.
- Deadlines use calibrated TSC ticks. A zero deadline means invalid or
  unavailable. Both hosted and native clock helpers reject arithmetic that
  would exceed signed 64-bit time before multiplying or adding.

## Exception classification and response

The IDT installs handlers for CPU exception vectors 0–31. The handler saves
all general registers and the CPU frame, disables interrupts, writes a fixed
report to COM1 and the framebuffer without allocating, and halts. The report
includes the vector, CPU error code when applicable, RIP, CS, RFLAGS, RSP,
CR2, and registers. A second fault while reporting goes directly to the halt
path. The `KernelBootInfo` panic fields at offsets 2600–2672 retain the first
report for a QEMU memory capture. Vector 255 means an unexpected interrupt.

| Vector | Classification | Useful evidence |
| --- | --- | --- |
| 14 | Page fault | CR2 is the fault address. Error bits 0–4 mean present/protection, write, user, reserved-bit violation, and instruction fetch. |
| 13 | General protection | Error code and RIP identify an invalid protection or noncanonical access. CR2 is unrelated to this fault. |
| 6 | Invalid opcode | RIP identifies the rejected instruction. |
| 8 | Double fault | The first exception could not be delivered safely; capture the report and reset. |
| Other 0–31 | CPU exception | Use the vector and architecture error code (if present) with RIP and register state. |

Ring-3 AUN1 page and protection faults are intercepted by the native user
runtime and terminate that child; they do not use the kernel panic path.
Checked AUEX faults similarly produce process fault records. A genuine
supervisor fault remains fatal because continuing after corrupted kernel
state is unsafe. This is the intended meaning of “survives controlled
faults”: the OS contains user faults; for kernel faults it records a stable
diagnosis and halts deliberately instead of continuing in an unknown state.

## Reproduction and verification

Run `make test-kernel-panic` from the OS repository. It boots debug KMon in
QEMU twice: `panic` reads unmapped page zero (vector 14), and `panic gp`
reads a noncanonical address (vector 13). Each run checks the serial report,
the framebuffer report, and retained `KernelBootInfo` fields. The command is
accepted only in debug boot mode. `make test-stage2-boot` exercises AHCI and
NVMe boot, TSC calibration, IRQ delivery, repeated allocation and mapping,
and stable resource counts after shell reads. `make test-native-user-mode`
checks ring-3 fault containment and continued PID 1/KMon operation.

The panic path is designed to operate without normal allocators and with
interrupts disabled. Serial output still depends on a working COM1 device;
the framebuffer path still depends on a valid GOP mapping. The current
checks cover QEMU/OVMF and do not establish behavior on every physical
machine or under SMP, which remains outside the present ownership model.
