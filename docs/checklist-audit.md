# Checklist ownership audit

This records the October 2026 cleanup pass across Australis and Hydrogen.
The source checklists remain the detailed progress records; a red item here is
still open, not a release claim.

| Area | Correct owner and disposition |
| --- | --- |
| Boot image rejection, boot-mode keys, and missing GOP | Bootloader. AHCI/NVMe negative-image and no-GOP QEMU tests plus default/S/N mode checks now cover these paths. `D` and `R` have separate KMon/recovery tests. |
| Firmware allocation and `ExitBootServices` failure injection, kernel payload integrity, ACPI, boot arguments, configuration, Secure Boot, and additional architectures | Bootloader. These need fault-injection hooks, a versioned image/configuration contract, or new platform targets. They remain open in [the bootloader checklist](../src/bootloader/README.md). |
| Cold boot, restart, and handoff on physical firmware and controllers | OS release validation. QEMU cannot close this hardware gate; it remains in the bootloader and [OS plan](../PLAN.md). |
| HyFS 2 allocation and consistency inspection | Storage. The kernel writer already protects both valid generations; the offline writer now reserves both too. The read-only `hyfs2.py check` command validates roots, objects, extents, and reports unreferenced nonzero blocks. See [the HyFS 2 plan](hyfs2-plan.md). |
| KMon `status` and `bootinfo` | Kernel recovery console. Both now have command and QEMU coverage. Retained `log`, native scheduling/syscalls, resource accounting, and fuller memory/permission policy remain kernel work in [its checklist](../src/kernel/README.md). |
| Shell file and administration commands, persistent services, capability grants, login/session policy, and graphical programs | Userland, after their kernel APIs exist. `inspector` already covers the old `finfo` role; `cat` covers simple text display, while a paged `view` and real `hexview` remain separate work. See [the userland checklist](../src/userland/README.md). |
| Native AUN1 source output, imports/package lookup, and compiler/runtime parity | Hydrogen compiler. The OS can run small AUN1 children but Hydrogen does not yet emit that format. See the compiler's `OS_ROADMAP.md` and `ROADMAP.md`. |
| Native compiler bootstrap memory and negative diagnostics | Hydrogen compiler. The SDK and native routes now accept `GC.Collect()` for the bootstrap source, which releases temporary parse and codegen data; the negative build suite requests diagnostic-only output. The repeated-generation proof passes with a documented 3 GiB address-space bound. |
| Installable `Hydrogen.*` and `Australis.*` packages | Hydrogen standard library. Its `ROADMAP.md` now distinguishes compiler prerequisites, OS contracts, and library implementation gates. Compiler builtins are not packages. |

The remaining red items are substantial target features or physical release
checks. Their checklist location is retained where it matches the owner; the
cross-layer dependencies above prevent a userland or library item from being
marked complete solely because a kernel or compiler primitive exists.
