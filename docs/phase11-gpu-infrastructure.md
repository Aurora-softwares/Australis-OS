# Phase 11 GPU infrastructure progress

The native VirtIO-GPU transport now negotiates `VIRTIO_GPU_F_VIRGL` when the
device offers it. The existing 2D feature path stays available when VirGL is
absent. On a VirGL device, the kernel reads the bounded capset count, queries
capset metadata, prefers VirGL2 over VirGL1, and creates a fenced context.
The native display backend keeps that context and one 64×64 render texture
until shutdown or reset.

`VirtioGpu3D` owns the first kernel context and a bounded B8G8R8A8 2D texture
resource. The resource path creates a host 3D texture, attaches DMA backing,
attaches it to the context, transfers its pixels to the host, and tears down
those attachments before unreferencing the resource and destroying the
context. The boot probe exercises a 64×64 texture, a VirGL no-op command,
surface pixel upload and readback, and a GPU texture clear followed by
readback on a GL-backed QEMU device. Clear colors can differ by one channel
level after the renderer's color conversion; the probe checks that tolerance.
Each command uses the existing fenced
control queue with response, fence, completion-length, and timeout checks.

`IRenderSurface` gives the software and VirGL implementations the same
`Clear`, `Upload`, `Readback`, and `Destroy` operations. The software surface
copies into an owned `PixelSurface`. The VirGL surface validates source and
destination geometry, copies pixels into 16 KiB of kernel-owned DMA backing,
and uses fenced 3D transfers. The native backend keeps this surface alive
while VirGL is available and releases it before closing the device.
If a 3D command fails, the context records a fault and refuses further
render operations. The native backend then reports acceleration unavailable;
its 2D scanout can continue. `Recover()` resets and reinitializes the device,
including the optional 3D surface. Cleanup still attempts to detach the
resource and destroy the context after a fault, and device close resets it
before DMA backing is released.

The submission API accepts at most 224 bytes of four-byte-aligned,
kernel-generated commands per request. It has no syscall or user-process
entry point. Untrusted clients cannot create contexts, name GPU resources,
or submit raw VirGL streams. DMA backing is allocated and released in the
kernel, after the device has acknowledged cleanup or been reset.

The compositor still draws into software RGB surfaces and uses the Phase 10
2D scanout path. The VirGL surface gives it a tested upload and clear target,
but window composition and scanout integration are still pending. Context and
texture ownership are currently single-context kernel operations; per-client
quotas and handles, validation for future client commands, and recovery of
3D faults without an explicit device recovery request remain for the rest of
Phase 11.

The command layouts follow the
[OASIS VirtIO 1.2 specification](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html).
The texture target, format, and bind values follow Mesa Gallium's
`PIPE_TEXTURE_2D`, `PIPE_FORMAT_B8G8R8A8_UNORM`, and render-target plus
sampler-view flags.

## Validation

- 🟢 `make test-graphics`: capset probe, fenced context lifecycle, texture
  create/upload/destroy command order, submission size rejection, and
  software render-surface contract, including demotion after a failed 3D
  command and context cleanup.
- 🟢 `make test-virtio-gpu-3d`: GL-backed QEMU device with an explicit render
  node; verifies a context, texture upload, software-to-GPU upload/readback,
  GPU clear/readback, command submission, cleanup, and a live native 2D
  display service through serial markers.
- 🟢 `make test-virtio-gpu`: AHCI/NVMe 2D scanout, mode changes, cursor, and
  GOP fallback when the requested mode exceeds native bounds.

QEMU's headless GL display does not expose a screenshot surface to the HMP
`screendump` command in this configuration, so the GL smoke test checks
texture pixels through 3D transfer readback and the live serial session.
Desktop pixels are verified by the ordinary 2D QEMU smoke test.
