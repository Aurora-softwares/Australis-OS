# Phase 7 graphics foundation

The graphics code has a bounded host-tested window model and a live AUEX
display service. Normal boot starts the service before the command shell when
the checked GOP mode supports it. The service composes two independent client
cell surfaces into separate overlapping windows and draws a movable mouse
cursor. Clicking a window focuses its client for USB keyboard and pointer
input; clicking wallpaper returns USB typing to the shell. COM1 stays
available to the shell, and framebuffer text output resumes when the service
exits. The service also owns live geometry and stacking: title drags move
windows, right and bottom edges resize them, and the coloured controls
close, minimize, and toggle maximize.

## Implemented contracts

- `PixelSurface` owns up to 1,048,576 RGB888 pixels. It validates dimensions,
  clips rectangles and circles, draws rounded rectangles, and composites
  another surface with a checked 0–255 opacity.
- `FramebufferPresenter` validates the captured GOP mode through
  `FramebufferMode`, clips presentation to that mode, and converts RGB pixels
  to the firmware's RGB or BGR 32-bit layout. Only its writer sees physical
  framebuffer addresses.
- `WindowLayout` tracks up to eight windows with monotonically increasing IDs,
  an owning process ID, bounded geometry, z order, focus, rounded hit testing,
  minimize/restore, maximize/unmaximize, move/resize, and owner cleanup.
- `WindowRenderer` copies submitted pixels into compositor-owned surfaces,
  paints two or more overlapping windows without crossing their bounds, and
  draws borderless rounded windows, coloured controls, hover icons, and the
  top bar. It blurs and tints the ordinary top bar and makes it black with
  merged controls when a window is maximized.
- `WindowInputRouter` focuses by hit test, captures content pointer input,
  moves floating windows from their title area, resizes from an invisible
  bottom-right grip, and applies the three window controls. Its bounded queue
  returns events only to the matching owner ID and discards events for closed
  or hidden windows. The live service uses its own two-window input path
  with the same basic controls and rounded hit regions.
- `DamageTracker` clips dirty rectangles to the display and falls back to a
  full-screen update after sixteen pending rectangles. `FramebufferPresenter`
  can present only these regions and clears them after a successful write.
  Composition itself still repaints the complete software frame.
- `DisplayDevice` grants one exclusive lease to a process with display
  capability bit `2`. Its AUEX calls claim/release the lease, fill a checked
  rectangle, and request a mode change. A fill must fit wholly inside the
  validated GOP mode and contains at most 65,536 pixels; callers never see
  the framebuffer address. The fixed GOP mode returns `-95` for SetMode.
  Process exit releases the lease and restores the framebuffer text mirror.
- `/System/Core/Display.exec` runs as a persistent AUEX child of PID 1.
  It spawns two separate AUEX clients, opens versioned channels to them,
  assigns one window ID to each channel, and retains a separate 4×4 RGB cell
  surface for each client. Create, update, and close requests are checked
  against that channel's ID. The service chooses geometry, stacking,
  decorations, and top bar before issuing checked display calls. A closed
  channel removes its window. Startup treats display failure as optional
  and continues to the serial shell. The second demo client closes and
  reopens its window during startup to exercise the live lifecycle.
- `Display.PollMouse(byte[3])` is available only to the current display
  lease owner. It returns button bits and signed motion encoded with a 128
  offset. The service draws a white and dark software cursor and restores
  the clipped scene beneath its old location on movement. The default
  graphical QEMU run target attaches both a USB keyboard and mouse.
- `Display.CaptureKeyboard(0|1)` and `Display.PollKey()` are available only
  to the display lease owner. The former switches USB keys between shell and
  service; COM1 remains attached to the shell. Lease release returns USB
  input to the shell. The two unprivileged demo clients verify these calls
  are denied.
- The live service hit-tests in current stacking order. It raises and
  focuses the clicked window, sends content pointer down/up and captured
  motion events only to that window's process-bound channel, and sends key
  events only to the focused client. A wallpaper click clears focus. Focused
  headers change colour; each client can update its own RGB cell on a key.
  The service clips cell, header, and cursor damage before recomposing those
  rectangles and falls back to a full-screen repaint if its sixteen-entry
  damage list fills. It restores only the first and final cursor rectangles
  in a batch of mouse reports, avoiding unnecessary full-screen repaints.
  It removes damage rectangles covered by a larger repaint, so movement
  and resizing do not repeat full window composition for focus, overlap,
  and cursor damage.
- The live windows have clipped rounded corners, focused title headers,
  red/yellow/green controls with hover icons, and invisible resize edges.
  A title drag moves a floating window; clicking a covered window raises it.
  Maximizing fills the workspace below the top bar and moves the controls
  into the black bar. Restoring returns the floating geometry and dark bar.
  Minimizing hides the client without closing it; its grey top-bar chip
  restores it. Closing terminates the matching client and removes its chip.
- Releasing the display lease restores the framebuffer text mirror, writes a
  recovery notice, and keeps the serial terminal contents intact. A fatal
  display-service input, channel, or redraw error releases the lease and
  returns a nonzero service status; the command shell remains available on
  COM1.
- The AUEX instruction watchdog resets after a successful cooperative
  `Process.Sleep`, so persistent services can keep running while tight loops
  without a yield still have a bounded instruction budget.

`make test-graphics` covers bounds and clipping, color conversion, ownership
checks, two-window overlap, focus, rounded corners, control hit regions,
maximize/restore, minimize/restore, pointer routing, owner-specific event
delivery, stale-event cleanup, invisible resize grips, dirty rectangles, and
the rendered top-bar transitions. It also checks exclusive display ownership,
checked rectangle writes, unsupported GOP mode changes, and mirror handoff.
`make test-display-ahci` and `make test-display-nvme` check the two client
surfaces and top bar in QEMU screenshots, rejected cross-window updates,
close and reopen handling, denied display and input calls by both clients,
cursor appearance and motion, restoration of covered pixels, top-window and
A-only pointer hits, pointer capture across overlapping windows, focus changes,
client-specific USB keys and cell updates, wallpaper focus release, serial
shell operation while the lease is held, rapid mouse bursts without display
corruption, title movement, edge resizing, stacking order, maximize and
restore, minimize and top-bar restore, hover icons, close, and KMon recovery
after exit. Release also verifies that serial output was not cleared.
`make test-display-fallback` removes the optional service from a disposable
image and checks that the serial shell still starts on AHCI and NVMe.
`make build` verifies that the modules compile into the kernel image.

## Beyond the Phase 7 demonstration

- Extend the 4×4 cell surfaces to arbitrary bounded client pixels through a
  chunk protocol or shared pages. Geometry and stacking still belong to the
  service; the richer host window model is not yet driven by live IPC.
- Improve software composition and rendering performance in Phase 8,
  including the planned frosted bar. The live Phase 7 bar is an opaque dark
  surface when windows float. The finished desktop shell is Phase 14 work.

Native AUN1 processes still have one 4 KiB data page and one 4 KiB stack
page, with a 256-byte transfer limit per syscall. A general client pixel
surface therefore needs a bounded chunk protocol or new shared-page mappings.
The current service uses version 2 AUEX channels for window creation, cell
updates, and closure. The kernel binds display calls to the authenticated
AUEX PID and checks the read-only capability manifest before granting a lease.

The intended interactions are described in `desktop-design.md`.

## Phase 7 validation status

- 🟢 Software surfaces and a checked GOP presenter: host graphics test and
  kernel build pass.
- 🟢 Process-authenticated display API and exclusive lease: host and QEMU
  tests pass; GOP mode setting is unsupported after firmware handoff.
- 🟢 User-space display server and two independent live windows: AHCI and
  NVMe QEMU screenshot tests pass with separate client PIDs and channels.
- 🟢 Live window ownership: each client has a server-assigned ID and bounded
  RGB cell surface; cross-client update attempts are rejected in QEMU.
- 🟢 Software cursor: mouse motion and covered-pixel restoration pass QEMU
  screenshot tests on AHCI and NVMe.
- 🟢 Live focus, hit testing, pointer capture, keyboard routing, clipping,
  and damage: QEMU exercises both clients, overlapping hits, USB keyboard
  handoff, and clipped redraw on AHCI and NVMe.
- 🟢 Live decoration controls, movement, resizing, and dynamic stacking:
  AHCI and NVMe QEMU screenshots verify title drags, edge resizing, raised
  overlaps, both maximize states, minimize/restore, hover icons, and close.

The Phase 7 completion criterion is met by the two independent interactive
demo windows. The fixed GOP mode is correctly reported as immutable after
handoff. There is no native display driver with a post-handoff mode-change
operation.

Validation on 2026-10-19: `make build`, `make test-graphics`,
`make test-stage5-host`, `make test-xhci-multi`, the AHCI and NVMe
display boot tests, and missing-service fallback tests pass. The display
tests inspect QEMU framebuffer pixels, move and click an emulated USB mouse,
exercise every live window control and geometry transition, route keys to
each client and back to the shell, verify covered-pixel restoration, and
exit the session to verify KMon recovery.
