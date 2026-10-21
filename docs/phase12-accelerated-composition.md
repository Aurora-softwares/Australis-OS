# Phase 12 accelerated composition progress

Phase 12 is in progress. The VirGL driver now accepts bounded partial texture
uploads, so a changed cell transfers only its rectangle. The display service
keeps a separate compositor-owned texture for each of its two application
windows. Window-sized allocation is limited to one million pixels per texture,
three textures for the display owner, and four texture slots globally. Ordinary
GPU clients retain a single 64×64 texture. Process-scoped handles, GPU
capability checks, and the exclusive display lease prevent cross-process
access to GPU resources and composition.

The GPU-backed per-window surface and software fallback item is verified by
the graphics tests and live VirGL boot probes. A separate render-target probe
now verifies source-alpha blending, but final window composition still needs
to use that draw pipeline.

`Gpu.BlitRegion` copies a validated source rectangle to a destination rectangle
inside an open compositor frame. The display service intersects each window's
content with the damage clip before invoking it. New windows initialize their
textures from their submitted colors, cell updates transfer the changed cell,
and resizing recreates the texture at the new size. If a texture operation
fails, the service draws the same content through its software path. GOP and
the 2D VirtIO-GPU backend continue to use that path.

`Gpu.CopyRegion` now copies a bounded rectangle directly between two
compositor-owned VirGL textures. The source resource is attached only for the
fenced copy, and both opaque handles must belong to the caller holding the
display lease. The live VirGL boot probe checks a copied pixel by reading the
destination texture and rejects an out-of-bounds copy. The CPU shadows are
updated after successful copies. Because all supported texture writes update
those shadows, the current software scanout composes from them without a
synchronous GPU readback for every window-content blit.

The kernel also has a bounded VirGL texture scanout and flush path. A boot
probe selects a 64×64 texture, flushes it, and disables that scanout before
the normal 2D display starts. This verifies that the device accepts a 3D
resource as a scanout target; the live compositor does not yet use it for
frames.

This is **not yet hardware-accelerated window composition**. The current
region blit copies its CPU shadow into the software frame. Window decorations,
rounded corners, transparency, transforms, stacking, and final scanout composition
are still CPU rendered. Removing the per-window readback eliminates one
drag-time stall, but does not establish smooth movement or GPU composition.
A GPU draw pipeline that blends and transforms window textures into
an output target, followed by correctness and frame-time comparisons, remains
necessary before the Phase 12 completion requirement can be met.

An alpha-enabled VirGL `BLIT` accepted a half-transparent source but copied it
as opaque, so the compositor needs render-target drawing with blend state. A
kernel boot probe now creates a framebuffer and shaders, draws a half-alpha red
triangle over green, reads back the center pixel, and checks that both red and
green channels are near half intensity. Its vertex buffer uses DMA-backed
VirtIO-GPU transfer. This proves blending works on the tested VirGL host;
sampling a window texture and drawing into the live scanout are still required.
During this work, the self-hosted Hylang compiler's failed direct-image result
was corrected so backend errors are no longer misreported as a kernel panic
entry-offset failure. Its regression test passes.

## Validation

- 🟢 `make build`: compiler, kernel, and userland images build.
- 🟢 `make test-graphics`: texture bounds/region transfers, GPU copy and 3D
  scanout command encoding, and clipped compositor region authorization pass.
- 🟢 `make test-stage5-host`: interpreter and user capability tests pass.
- 🟢 AHCI and NVMe VirGL boot probes: window-sized allocation, two live GPU-backed
  contents, region blit bounds, texture-to-texture copy/readback, 3D scanout
  setup/flush/teardown, and resource isolation pass.
- 🟢 Live VirGL alpha draw/readback probe: render-target blend state, shaders,
  DMA-backed geometry, and expected mixed-color pixels pass on tested QEMU.
- 🟢 AHCI and NVMe Stage 2 boots and software display fallback pass. The NVMe
  boot was rerun successfully after one QEMU launch timeout.
- 🟢 `make test-virtio-gpu`: native 2D scanout remains correct with AHCI,
  NVMe, VGA primary, and clamped oversized modes.
- 🔴 Window-texture sampling, GPU compositor output comparison, transforms, and
  measured drag performance remain.
