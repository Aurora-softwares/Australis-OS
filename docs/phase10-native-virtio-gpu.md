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
hardware-cursor availability in bit 28. The driver acknowledges the device
event and asks for fresh display information. A successful geometry change
recreates the scanout resource, revokes old presentation handles, reshapes
the kernel-owned drawing surfaces, and resets frame pacing and damage. The
display service polls this contract, updates its layout, and redraws the
entire desktop. Pressing `m` in the focused desktop toggles between 1280×800
and 1024×768 for the live mode test. Automatic recovery still requires GOP
and native modes to match before switching to GOP.

When the second VirtIO-GPU queue is available, the driver creates a separate
64×64 B8G8R8A8 cursor resource backed by DMA pages. It transfers the image
through the control queue and submits fenced update and move commands through
the cursor queue. Cursor motion does not require a full desktop redraw. The
display service keeps its software cursor path for GOP or a native device
without a usable cursor queue. Cursor resources and queue pages are released
on shutdown or reset. QEMU's cursor queue completes with zero response bytes;
the driver accepts that completion while validating normal response headers
when a device supplies one. The default `virtio-vga` boot test requires the
hardware cursor to be active.

`make run` now presents a single `virtio-vga` display, so the normal QEMU
desktop selects the native 2D backend and cursor queue. The SDL display
preserves the VirtIO-GPU cursor shape when QEMU grabs relative mouse input;
GTK replaces it with a blank cursor, or the host pointer when
`show-cursor=on` is set. Override `QEMU_DISPLAY` to use another display
frontend. Oversized display modes are
limited to the kernel's supported 1280×800 scanout instead of triggering GOP
fallback. Use `make run-gop` to exercise the software cursor and GOP fallback.
The run targets boot the existing ISO; after editing sources, use `make all`
before `make run`. `make iso` and `make iso-hyfs2` name the same HyFS2 target.
`make build && make iso` also works when packaging without rebuilding apps.
`make build iso` in one Make invocation can use a stale packaging signature.
The cursor queue decouples ordinary pointer motion from desktop damage, but
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
  persistent native backend, hardware cursor movement, live
  1280×800 → 1024×768 → 1280×800 mode changes, and desktop pixels after
  each change. It also boots an oversized GPU mode and checks that the
  native scanout is limited to 1280×800. QEMU's `screendump` omits the hardware
  cursor overlay, so the
  smoke test checks cursor commands by their successful serial marker;
  software cursor pixels are sampled when hardware cursor setup is absent.
- 🟢 `make test-cursor-stress` keeps the default hardware cursor active under
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
