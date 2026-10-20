# Memory protection contract (Phase 2)

The supported native AUN1 path uses x86-64 ring 3 and a private CR3 root per
launch. The AUEX compatibility runtime still executes checked bytecode in the
kernel. The guarantees below apply to AUN1 and were exercised in QEMU/OVMF on
AHCI and NVMe. They are the completion criteria for the present Phase 2 scope.

## Checklist and ownership

- 🟢 Virtual memory: the bootloader clones the firmware page tables and
  removes page zero; the kernel allocates, maps, translates, and unmaps 4 KiB
  pages in a separate dynamic slot. Each AUN1 launch allocates its own PML4,
  PDPT, directory, leaf table, and user frames. Release returns its frames and
  table pages only after the kernel CR3 has been restored.
- 🟢 Kernel and user separation: the private root copies kernel mappings
  with the user bit cleared at PML4 level. The one user PML4 slot contains only
  pages owned by that launch. A startup check rejects a private root with a
  user-accessible kernel PML4 entry. Supervisor mappings remain available to
  interrupt and syscall handlers while the user CR3 is active.
- 🟢 Write versus execute: code is user readable and executable but not
  writable. The data and stack pages are writable and NX. New kernel dynamic
  mappings are NX; the trusted native runtime shim has a read-only executable
  alias. No dynamic mapping API accepts writable plus executable flags.
- 🟢 Guarded stacks and switching: page 4 is the one-page stack; adjacent
  pages 3 and 5 are absent. Entry saves the kernel CR3, stack, and interrupt
  state, updates TSS.RSP0, then enters ring 3. Exit and contained exceptions
  restore CR3, stack, and the caller's interrupt state before returning.
- 🟢 Fault recovery and hostile pointers: user page, general-protection,
  invalid-opcode, and divide faults terminate the native child. Kernel faults
  continue to the allocation-free panic handler. The serial write syscall
  accepts only a complete range in one known mapped user page; even a launch
  without a startup record has a zeroed data page. Invalid and page-crossing
  ranges return `-14` before dereference.

## Address layout

The base is selected from a vacant lower-half PML4 slot beyond the kernel
dynamic slot. Offsets are relative to that base:

| Page | Permission | Use |
| ---: | --- | --- |
| 0 | Unmapped | Null-side guard |
| 1 | User, read, execute | AUN1 code and inline literals |
| 2 | User, read, write, NX | AUSP startup record or zeroed data |
| 3 | Unmapped | Stack underflow guard |
| 4 | User, read, write, NX | Stack, with initial RSP at its top |
| 5 | Unmapped | Upper stack guard |

The ABI currently limits each native program to one code, one data, and one
stack page. This is a deliberate bounded AUN1 profile; a general purpose
native heap, stack growth, and a wider syscall API belong to the later
process and syscall phases. Timer-driven preemption is described in
`process-scheduling.md`.

## Verification

`make test-native-user-mode` builds the Hydrogen AUN1 source fixture and
adversarial native images, then boots the same ISO on AHCI and NVMe. It checks
PID and exit, invalid syscall pointers (including null, kernel, guard, and
cross-page ranges), a read and write of the real `KernelBootInfo` address,
attempts to write code and execute the data page, stack underflow, privileged
instructions, invalid opcodes, and divide errors. Every child fault is followed
by a working PID 1 shell; the test exits PID 1 and checks KMon as well.

The inherited bootloader/firmware identity mappings have not been converted
to a kernel-wide W^X layout. They are supervisor-only while AUN1 runs, so
they do not grant user access. Tightening those bootstrap aliases and testing
on real hardware remain separate hardening work; this contract does not claim
kernel-wide W^X or physical hardware validation.
