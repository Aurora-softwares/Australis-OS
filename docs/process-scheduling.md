# Processes and scheduling (Phase 3)

Australis runs AUEX compatibility programs in the kernel's checked bytecode
scheduler and AUN1 programs as x86-64 ring-3 threads. Both use the same PID
sequence, parent/child status table, and wait result conventions. The current
implementation runs on one bootstrap CPU; each AUN1 process has one native
thread and its own address space.

## Phase 3 contract

- 🟢 Process and thread ownership: `UserProcessTable` owns PID, parent PID,
  capability bits, lifecycle state, exit status, and fault. `NativeUserTask`
  owns one private address space and a zeroed physical page containing the
  15 general registers and five-word user return frame. Native thread states
  are runnable, running, exited, faulted, and terminated. The scheduler owns
  runnable tasks; a terminal result stays available until the parent reaps it.
- 🟢 Ring-3 entry and return: each slice saves kernel CR3, RSP, and IF in
  `KernelBootInfo`, sets TSS.RSP0, switches to the task's CR3, restores its
  registers, and enters through `iretq`. Exit and user faults restore the
  kernel state before managed code can free task resources.
- 🟢 Context switching and preemption: the periodic local APIC timer saves
  the interrupted ring-3 registers and return frame to the task context,
  acknowledges the interrupt, and returns to the scheduler. A round-robin
  native queue runs one timer-bounded slice at a time. The AUEX scheduler
  gives a native child a turn each round, so AUEX and AUN1 children can both
  make progress. Kernel-mode timer interrupts keep their existing handler.
- 🟢 Termination and limits: at most 16 native tasks may exist at once.
  A task is stopped after 16 timer yields or 4096 managed channel calls if it
  has not exited. Termination uses a distinct fault result. Exit, fault,
  timeout, and termination release
  its user frames, page tables, and saved context before publishing the final
  result. One result slot remains until its parent waits or exits.
- 🟢 Parent/child lifecycle: only a recorded parent can wait on or terminate
  a child. Completed children of a live parent are retained until reaped.
  A second wait fails. Parent exit terminates and reaps outstanding children;
  terminal handles and IPC channels are closed with the child.

## Verification

`make test-native-user-mode` boots QEMU/OVMF on AHCI and NVMe. Its boot probe
starts a non-terminating native task, confirms that the timer preempts it,
runs a second task to a successful exit, and terminates the first. The
`native-schedule-probe` AUEX program then spawns four native children together:
a spinner, a PID/exit child, a deliberate page-fault child, and a child that
checks its registers and private data after a long timer-driven loop. It
checks exit values, fault values, invalid repeated/foreign waits, explicit
termination, and continued operation of PID 1 and KMon. Repeated runs of
`native-orphan-probe` verify that parent exit reclaims a still-running native
child and frees its task slot. The hosted
`make test-stage5-host` suite checks that unreaped child records survive
bounded history recycling and that repeated reaping is rejected.

Native scheduling is currently single-CPU and uses one thread per AUN1
process. AUN1 is still restricted to the read-only system bin directory and
its terminal, PID, exit, and invited-channel syscall set. Native filesystem
and device APIs, SMP, multi-threaded processes, and general application
packaging are later work.
