# Phase 8 software rendering and performance

The live display service now builds each redraw in a kernel-owned RGB
backbuffer. It submits all dirty regions through `BeginFrame` and
`PresentFrame`, so an incomplete redraw is never exposed between regions.
The service yields between regions to stay inside the AUEX instruction budget;
the same frame remains open across those yields. `DisplayDevice` keeps the
backbuffer between frames and presents only its accumulated damage through
the checked GOP writer. A repeated `BeginFrame` records a superseded frame
and retains pending damage. The kernel permits a new GOP frame at least
16 ms after the preceding frame completed. An early `BeginFrame` returns
`-11`; the service sleeps and retries with its dirty regions intact.

The host compositor supports `ComposeRegion` and `ComposeDamage`. It clips
wallpaper, window content, rounded corners, controls, and the top bar to each
dirty rectangle. Its wallpaper gradient and blurred, tinted bar are cached;
an opaque region copy restores them during redraw. Window interiors are
painted as clipped rows, with rounded-corner checks confined to edge rows.
The `PixelSurface` blitter uses row indices after one bounds check, and the
GOP presenter computes each row's framebuffer address once. The live service
retains its simpler opaque bar and 4×4 client cell surfaces.

## Measurement

Run `make benchmark-graphics` to regenerate
`build/graphics-benchmark.json`. The native host workload draws and presents
640×480 RGB frames, composites two overlapping windows, and repeats a 64×64
dirty update. The script reports the median of three timed runs after one
warm-up, including process startup. It requires partial composition and
presentation to beat their full-frame counterparts by at least 4× per frame.
These are host CPU measurements with a counting framebuffer writer, not a
QEMU display refresh rate.

On 2026-10-19, the measured full composition was 8.75 ms per frame versus
0.45 ms for a 64×64 region (19.34× per-frame difference). The full
composition baseline before caching and row painting was 66.59 ms per frame.
Full mock framebuffer presentation was 15.77 ms per frame versus 0.224 ms
for the 64×64 region. Opaque full-surface copying was 2.08 ms per frame;
half-opacity blending was 13.36 ms per frame. The figures vary with host
load, so the benchmark is a regression signal rather than a fixed deadline.

`Display.Stats(byte[20])` exposes submitted, presented, and superseded frame
counts plus last and maximum BeginFrame-to-GOP-completion latency in
microseconds. The first live frame checks the counters before the display
service announces readiness. The host graphics test checks deferred writes,
dirty pixel counts, counter reset, superseded frames, a deterministic latency
clock, and the exact 16 ms admission boundary. After two live frames, the
service reports its frame count, last and maximum latency, and number of
pacing waits on COM1. It also compares partial composition against a full
reference after moving, hovering, and maximizing overlapping windows.

## Native VirtIO exercise

The Phase 8 VirtIO PCI code parses the modern GPU's vendor capabilities,
validates common, notification, ISR, and device regions, computes notification
offsets, and models a bounded split queue with request and response
descriptors. The 2D resource manager encodes fenced create, attach, scanout,
transfer, flush, detach, and unref commands with checked geometry and backing
size. Host tests cover capability traversal, queue busy/completion checks,
command order, dirty transfer offset, and attach failure rollback. These
layouts follow the [OASIS VirtIO 1.2 specification](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html).

The native probe discovers the PCI GPU, maps its capability BARs, negotiates
`VIRTIO_F_VERSION_1`, allocates a physical split ring and command buffers,
submits fenced commands, polls bounded completions, and validates response
types and fence IDs. It creates a 32×32 resource backed by a guest page,
attaches scanout 0, transfers and flushes pixels, then disables scanout,
destroys the resource, resets the device, and releases its mappings and pages.
The same sequence passes on AHCI and NVMe QEMU boots with a VirtIO-GPU PCI
device attached. A missing GPU leaves normal GOP boot untouched.

This was the Phase 8 probe. Phase 9 established the backend and buffer
ownership contract; Phase 10 extends this control path into a persistent
native display driver. See `phase10-native-virtio-gpu.md` for the live scanout
and recovery path.

## Validation

- 🟢 `make test-graphics`: surface, damage, full-versus-partial image,
  backbuffer, metrics, and VirtIO model tests.
- 🟢 `make benchmark-graphics`: seven workloads and partial rendering
  frame-time regression checks.
- 🟢 `make build` and `make test-stage5-host`: kernel, AUEX display intrinsics,
  and system-call contracts compile and pass.
- 🟢 `make test-display-ahci` and `make test-display-nvme`: QEMU framebuffer
  screenshots and complete mouse, keyboard, window, and recovery sequences.
- 🟢 `make test-display-fallback`: missing-service GOP console recovery on
  both AHCI and NVMe.
- 🟢 `make test-virtio-gpu`: live PCI controlq and 2D resource lifecycle on
  AHCI and NVMe QEMU boots.
- 🟢 `make test-frame-pacing`: AHCI and NVMe mouse workloads report complete
  frame counts, pacing admission, and measured latency.

The service uses a 16 ms minimum frame interval and cooperative yields. This
bounds submission rate without waiting inside the kernel; it does not claim
hardware refresh synchronization. On 2026-10-19, the live QEMU test measured
2.13 seconds on AHCI and 2.25 seconds on NVMe for the first reported redraw.
It permits up to 10 seconds as a gross-regression limit. The interpreted
userland service and emulated framebuffer have much higher latency than the
native host benchmark; its 16 ms interval is an admission limit, not a claim
of 60 frames per second.
