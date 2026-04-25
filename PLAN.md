# Australis OS Active Plan

This file tracks completed milestones and the active development plan for each phase.
It is a companion to the Australis-Docs roadmap and the Hylang-Compiler OS_ROADMAP.md.

## Current Status

- [x] Phase 0: Bootable UEFI application is complete
- [ ] Phase 1: Keyboard input and character echo — implementation complete, pending QEMU verification
- [ ] Phase 2: Minimal command prompt has not started
- [ ] Phase 3: Diagnostics and panic handler has not started
- [ ] Phase 4: Memory and runtime strategy has not started
- [ ] Phase 5: Hydrogen rewrite is blocked on Hylang-Compiler OS_ROADMAP.md phases UEFI-A through OS-A

## Phase 0 Closeout

Status: complete

- [x] Compile a C# source file to a native UEFI EFI binary with bflat `--stdlib:zero --os:uefi --arch:x64`
- [x] Boot the binary in QEMU with OVMF firmware
- [x] Clear the UEFI console on startup
- [x] Print a fixed boot message
- [x] Stay alive in an infinite loop after the message
- [x] Produce a FAT disk image containing the EFI binary at the standard removable-media path
- [x] `make build`, `make image`, `make run`, and `make clean` all work
- [x] Confirm the binary is a well-formed PE32+ EFI application (verified with `file`)

## Phase 1: Keyboard Input and Character Echo

Status: next

Goal: replace the idle infinite loop with a keyboard polling loop so that keys pressed
by the user appear on screen. This proves that Australis OS can receive and respond to
input — the minimum bar for any interactive system.

Everything in this phase stays in C# via bflat. No kernel architecture changes are
needed yet; this is purely an input/output loop.

### How UEFI Keyboard Input Works

UEFI provides keyboard access through `EFI_SIMPLE_TEXT_INPUT_PROTOCOL`, which is
available at startup via `SystemTable->ConIn`. The protocol has two relevant members:

- `ReadKeyStroke(protocol, out key)` — reads one key if available; returns
  `EFI_SUCCESS` (0) if a key was ready, `EFI_NOT_READY` (0x80000006) if the
  keyboard buffer was empty
- `WaitForKey` — an EFI event handle that can be passed to `WaitForEvent` to block
  until a key is pressed without busy-looping

An `EFI_INPUT_KEY` has two fields: `ScanCode` (a UINT16 that is non-zero for
special keys such as arrows, F-keys, and Escape) and `UnicodeChar` (a CHAR16 that
holds the printable character, zero for special keys).

In bflat's UEFI C# environment, `Console.ReadKey(intercept: true)` maps to
`ReadKeyStroke` under the hood. `Console.ReadKey` is available with `--stdlib:zero`;
however, `ConsoleKeyInfo.KeyChar` and several `ConsoleKey` named members (Enter,
Backspace) are not exposed in the zero stdlib. The implementation uses `(int)key.Key`
to read the raw character code and compares against integer char literals instead.
`ConsoleKey.Escape` is available (scan-code-based) and is used directly.
`Console.Write` only accepts `char` in the zero stdlib, so multi-character erase
sequences are written as individual `Console.Write(char)` calls.

The Makefile `RUN_WITH_LOCAL_LIBS` was also updated to place system libc++ paths
before `tools/lib`, which contains bflat stub files the OS dynamic linker cannot load.

### Checklist

Input loop:

- [x] Replace the empty `while (true) { }` with a loop that polls `Console.ReadKey(intercept: true)` (or raw `ReadKeyStroke` if `ReadKey` is unavailable in `--stdlib:zero`)
- [ ] Verify that key presses unblock the loop and return valid key data in QEMU
- [x] Echo printable `UnicodeChar` values back to `Console.Write(char)` on screen

Cursor:

- [x] Print a blinking-style prompt character (underscore `_`) at the current cursor position before each read
- [x] Erase the prompt character before echoing the typed character so they do not overlap

Special key handling:

- [x] Enter (`UnicodeChar == '\r'`): move the cursor to the start of the next line, reset the current line buffer
- [x] Backspace (`UnicodeChar == '\b'`): if there is at least one character on the current line, move the cursor back one column, print a space to erase the character, move back again
- [x] Escape (`ScanCode == 0x0017`): clear the screen and reset to the top-left, discarding the current line buffer
- [x] Ignore all other non-zero `ScanCode` values (arrow keys, F-keys) for now

Line buffer:

- [x] Keep a fixed-length character array (for example 160 chars, one screen width) representing the current input line
- [x] Append printable characters to the buffer on echo
- [x] Truncate input silently if the line buffer is full rather than overflowing
- [x] Reset the buffer on Enter or Escape

Boot message:

- [x] Update the boot message from `"Australis OS booted from C#"` to include a
  brief prompt hint, for example `"Australis OS v1 — press keys to echo"`
- [x] Print the message before entering the input loop

Verification (requires QEMU with display):

- [ ] Type a sequence of printable characters in QEMU and confirm they appear on screen
- [ ] Press Backspace and confirm the last character is erased correctly
- [ ] Press Enter and confirm the cursor moves to a new line
- [ ] Press Escape and confirm the screen clears and the cursor returns to the top-left
- [ ] Hold down a key and confirm the repeat stream is handled without hanging or corrupting the display

### Exit Criteria

- Any key pressed on the QEMU keyboard appears on the UEFI console immediately
- Backspace, Enter, and Escape behave as specified
- The display does not corrupt or freeze under rapid or held-key input

## Phase 2: Minimal Command Prompt

Status: not started

Goal: give the keyboard echo loop a command parser so that typed lines are interpreted
as commands rather than just echoed character by character. This turns Australis OS into
an interactive — if minimal — system.

Checklist:

- [ ] On Enter, pass the accumulated line buffer to a command dispatcher
- [ ] Implement `help` — print a list of available commands
- [ ] Implement `clear` — clear the screen and reset the cursor
- [ ] Implement `echo <text>` — print the rest of the line back
- [ ] Implement `version` — print the OS version string
- [ ] Implement `reboot` — call `EFI_RUNTIME_SERVICES.ResetSystem(EfiResetCold, ...)`
- [ ] Implement `shutdown` — call `EFI_RUNTIME_SERVICES.ResetSystem(EfiResetShutdown, ...)`
- [ ] Print an error message for unrecognised commands rather than silently ignoring them
- [ ] Show a command prompt prefix (for example `A>`) before each input line
- [ ] Update the boot message to reflect v2

Exit criteria:

- `help`, `clear`, `echo`, `version`, `reboot`, and `shutdown` all work in QEMU
- Unrecognised input produces a short error line rather than corrupting the display

## Phase 3: Diagnostics and Panic Handler

Status: not started

Goal: give the OS a controlled failure path. Right now any crash is silent and the
machine hangs or resets with no information. A panic handler makes development
significantly less painful from this point forward.

Checklist:

- [ ] Add a `Panic(string message)` function that:
  - Clears the screen
  - Prints `PANIC:` followed by the message in a distinct way (e.g. all-caps or with a border)
  - Halts the system in a tight loop so the message stays on screen
- [ ] Add a `Assert(bool condition, string message)` helper that calls `Panic` on failure
- [ ] Verify the panic path works by triggering it deliberately from the command prompt (e.g. `panic` command)
- [ ] Add a `meminfo` command that prints basic UEFI memory map information via `EFI_BOOT_SERVICES.GetMemoryMap`
- [ ] Add a `firmware` command that prints the UEFI firmware vendor string and revision from `EFI_SYSTEM_TABLE`
- [ ] Document in the Australis-Docs internals section how to read the panic output in QEMU

Exit criteria:

- A panic prints a message that stays on screen rather than hanging silently
- `meminfo` and `firmware` commands run without crashing
- Developers can distinguish a panic from a normal hang

## Phase 4: Memory and Runtime Strategy

Status: not started

Goal: establish how Australis OS will own its own memory from this point forward. This
is the last C# phase and its primary purpose is to design the memory model and prepare
the codebase for the Hydrogen rewrite in Phase 5.

Checklist:

- [ ] Call `EFI_BOOT_SERVICES.GetMemoryMap` on startup and print a summary (total usable RAM, largest contiguous region)
- [ ] Call `EFI_BOOT_SERVICES.ExitBootServices` to take ownership of the machine from the firmware
- [ ] After `ExitBootServices`, confirm the OS continues to run (the idle loop or command prompt must still work)
- [ ] Implement a trivial bump allocator over one of the usable memory regions identified from the memory map
- [ ] Implement `memset` and `memcpy` as standalone unsafe functions that do not depend on bflat stdlib
- [ ] Add a `heaptest` command that allocates, writes, reads back, and frees several blocks to verify the allocator
- [ ] Document the memory map layout and chosen heap region in Australis-Docs
- [ ] Review and remove any bflat stdlib features that will not be available after the Hydrogen rewrite (floating-point, reflection, threading, etc.)
- [ ] Add a `Hydrogen integration ready` note to the Australis-Docs roadmap once this phase is done

Exit criteria:

- The OS takes ownership of memory from UEFI firmware and manages a basic heap
- `ExitBootServices` succeeds and the OS continues operating normally afterwards
- The codebase has no remaining dependency on bflat stdlib features that Hydrogen cannot replace

## Phase 5: Hydrogen Rewrite

Status: blocked — requires Hylang-Compiler OS_ROADMAP.md phases UEFI-A through OS-A

Goal: replace every C# and bflat dependency with Hydrogen source. The output of
`make build` becomes a Hydrogen-compiled EFI binary instead of a bflat-compiled one.
This is the milestone where Australis OS is 100% Hydrogen, end to end.

This phase cannot begin until the following are complete in the Hylang-Compiler
repository (see `OS_ROADMAP.md` in that repo for the full plan):

- Phase UEFI-A: Hydrogen native compiler can emit a valid PE32+ EFI binary
- Phase UEFI-B: `[UefiEntry]` attribute and no-runtime mode are implemented
- Phase UEFI-C: Unsafe struct bindings exist for core UEFI protocols
- Phase UEFI-D: Minimal UEFI standard library (`UefiConsole`, `UefiMemory`, `UefiBootServices`)

Once those are ready, this phase proceeds as follows:

- [ ] Add a `.hyproj` manifest for the OS kernel source
- [ ] Translate `src/boot/Program.cs` to `src/boot/Program.hy` using `[UefiEntry]`, `Hydrogen.Uefi.Console`, and `Hydrogen.Uefi.Memory`
- [ ] Translate the command dispatcher, panic handler, and memory routines from Phase 1–4 into Hydrogen
- [ ] Update the Makefile to invoke `hyc compile src/boot/Program.hy --target uefi-x64 -o build/efi/EFI/BOOT/BOOTX64.EFI` instead of bflat
- [ ] Remove `tools/bflat/` and `tools/debs/` and `tools/lib/` from the repository
- [ ] Remove `src/boot/Program.cs`
- [ ] Boot the resulting image in QEMU/OVMF and confirm full feature parity with Phase 4
- [ ] Update the README and Australis-Docs to document the Hydrogen build path
- [ ] Update the boot message from `"Australis OS booted from C#"` to `"Australis OS booted from Hydrogen"`

Exit criteria:

- `make build` compiles Hydrogen source to `BOOTX64.EFI` with no C#, no bflat, and no external assembler or linker
- The image boots in QEMU/OVMF and all Phase 1–4 features work as before
- No C# or bflat files remain in the repository

## Notes

Phases 1 through 4 develop OS features in C# using bflat as the compiler bridge. This
is intentional — it lets the OS grow in capability while the Hydrogen compiler finishes
its UEFI output and no-runtime work in parallel. The two tracks are independent until
Phase 5 joins them.

The order within Phases 1–4 matters. The keyboard loop (Phase 1) proves interactive
input before any parsing is added (Phase 2). The panic handler (Phase 3) makes memory
work in Phase 4 far less painful to debug. Do not skip ahead.
