# Phase 10 native VirtIO-GPU 2D display

Australis now keeps the modern PCI VirtIO-GPU control queue alive after boot
and uses it as a display backend. `GET_DISPLAY_INFO` selects the first enabled
scanout whose dimensions fit the existing display buffer limit. The driver
creates a B8G8R8X8 resource, attaches contiguous guest backing, sets the
scanout, and transfers and flushes each damaged rectangle with fenced
commands. The compositor continues to draw RGB pixels through `DisplayDevice`;
applications cannot address the GPU resource or DMA memory.

The control queue has a bounded request area and a 512-byte response area for
display information. It checks completion length, response type, fence ID,
and transport status. The resource manager checks geometry, transfer bounds,
page alignment, and backing length. Resource backing comes from the kernel DMA
allocator, which does not expose it to user processes. The bootloader reserves
two contiguous slices of 64 and 1024 low pages. Storage bootstrap uses the
first 16 pages of the combined interval; the remaining 1072 pages form the
shared DMA pool. The UEFI image builder now publishes that combined interval
in boot information when multiple literal allocations are used.

`AdaptiveDisplayBackend` prefers the native backend and selects GOP if the
device is missing or initialization fails. After a failed native submission,
it resets and rebuilds the GPU resource, then resends the complete frame. If
that fails, it switches to GOP when the two scanouts have equal dimensions.
Display buffer handles remain owned by the display lease and are revoked on
process exit. The GPU resource belongs to the kernel backend, so an
application or compositor exit cannot leave an application-owned GPU resource.

The native display owner may call `Display.SetMode(width, height)` to request
a bounded 2D mode. `Display.SetMode(0, 0)` polls the device display-change
event and returns the current width in bits 0–15, height in bits 16–27, and
backend-managed cursor availability in bit 28. The driver acknowledges the device
event and asks for fresh display information. A successful geometry change
recreates the scanout resource, revokes old presentation handles, reshapes
the kernel-owned drawing surfaces, and resets frame pacing and damage. The
display service polls this contract, updates its layout, and redraws the
entire desktop. Pressing `m` in the focused desktop toggles between 1280×800
and 1024×768 for the live mode test. Automatic recovery still requires GOP
and native modes to match before switching to GOP.

The native backend draws a 14×20 pointer directly into the VirtIO-GPU scanout.
It saves the pixels beneath the pointer, restores them on movement, and
transfers and flushes only the changed pointer region. Nearby positions use
one combined GPU update. Queued motion reports are combined when the desktop
falls behind; button transitions are delivered individually. This keeps
pointer motion independent of a full desktop redraw and makes the pointer
visible in the guest image even when QEMU grabs the host mouse. Desktop
damage is copied beneath the pointer before it is repainted. The display
service keeps its software cursor path for GOP or if the native cursor stops
working. The VirtIO-GPU cursor queue API remains available for other clients,
but the normal desktop uses the scanout cursor.

`make run` presents a single `virtio-vga` display with an xHCI USB mouse, so
the normal QEMU desktop selects the native 2D backend and receives guest mouse
reports. The pointer is part of the guest scanout; QEMU's host cursor grab
does not control its visibility. Override `QEMU_DISPLAY` to use another
display frontend. Oversized display modes are
limited to the kernel's supported 1280×800 scanout instead of triggering GOP
fallback. Use `make run-gop` to exercise the software cursor and GOP fallback.
The run targets boot the existing ISO; after editing sources, use `make all`
before `make run`. `make iso` and `make iso-hyfs2` name the same HyFS2 target.
`make build && make iso` also works when packaging without rebuilding apps.
`make build iso` in one Make invocation can use a stale packaging signature.
The scanout cursor decouples ordinary pointer motion from desktop damage, but
window dragging and other scene changes still wait for the software
compositor's synchronous redraw. The 16 ms pacing setting is a minimum
interval, not a measured 60 fps refresh rate.

The command and response layouts follow the
[OASIS VirtIO 1.2 specification](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html).

## Validation

- 🟢 `make test-graphics` checks mode parsing, resource and cursor command
  bounds, mode-change buffer revocation, device-event polling, and native
  recovery followed by GOP fallback in the backend model.
- 🟢 `make test-virtio-gpu` boots AHCI and NVMe in QEMU with xHCI attached,
  including the default `virtio-vga` configuration; it verifies the
  persistent native backend, visible scanout cursor movement, live
  1280×800 → 1024×768 → 1280×800 mode changes, and desktop pixels after
  each change. It also boots an oversized GPU mode and checks that the
  native scanout is limited to 1280×800. QEMU's `screendump` includes the
  scanout pointer, so the smoke test samples its pixels before and after
  movement and checks that the old position was restored.
- 🟢 `make test-cursor-stress` keeps the default scanout cursor active under
  sustained xHCI mouse reports, checks that the shell remains responsive,
  and bounds managed allocator growth during idle and motion. The kernel
  reuses its mouse report and the user process reuses its IPC receive buffer,
  avoiding an allocation on every empty poll.
- 🟢 `make test-display-ahci` and `make test-display-nvme` keep the no-GPU GOP
  desktop and input path covered.
- 🟢 `make test-display-fallback` checks serial recovery when the optional
  display service is absent on AHCI and NVMe.

Device-originated display-change events are covered by the host model;
the QEMU smoke test exercises explicit live mode requests. GOP does not
implement live mode changes. GOP fallback after a runtime native failure
requires matching geometry.
