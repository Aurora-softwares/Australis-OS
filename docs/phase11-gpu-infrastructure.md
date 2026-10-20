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
its 2D scanout can continue. On a subsequent display poll or presentation,
the backend makes a bounded automatic recovery attempt while the control
queue is healthy. It detaches the old texture and context, clears the owned
backing, then recreates the context and texture before reporting acceleration
available again. Failed cleanup leaves the backing owned until device reset;
there is no attempt to reuse an uncertain resource ID. Full `Recover()` still
resets and reinitializes the device, including the optional 3D surface.

The submission API accepts at most 224 bytes of four-byte-aligned,
kernel-generated commands per request. It has no syscall or user-process
entry point. Untrusted clients cannot name GPU contexts or resources, or
submit raw VirGL streams. DMA backing is allocated and released in the
kernel, after the device has acknowledged cleanup or been reset.

Capability bit `4` in the read-only `AUSC1` manifest permits the semantic
`System.Australis.Gpu` calls. `Create(width, height)` (opcode 121) accepts a
texture no larger than 64×64, returns a positive process-scoped opaque handle,
and enforces one texture (16 KiB of DMA backing) per process and four textures
globally. The kernel allocates a separate VirGL context and resource ID for
each live texture. `Destroy(handle)` (122), `Clear(handle, rgb)` (123),
`FillRect(handle, x, y, width, height, rgb)` (124), and
`ReadPixel(handle, x, y)` (125) validate the caller's PID, handle, geometry,
and RGB values before issuing fixed kernel-generated commands. They never
accept command bytes, addresses, or host resource IDs. A stale or foreign
handle returns `-13`. Process exit tears down its context and texture;
failed teardown quarantines backing until the control device is reset.
Native device reset revokes all client handles.

`Gpu.Blit(handle, x, y)` (126) additionally requires display capability bit
`2` and the active display lease. It reads the caller's texture into the
compositor's current frame and marks that region damaged, so the normal 2D
scanout or GOP path presents it. The display service exercises an 8×8 GPU
tile inside one window cell. This is the Phase 11 connection between an
accelerated render surface, composition, and scanout; general accelerated
window blending and full-frame composition remain Phase 12 work.

The compositor still draws most of each frame into software RGB surfaces.
On native device loss during presentation, the adaptive backend resets the
2D scanout and its 3D contexts together, rebuilds their backing, marks the
software frame fully damaged, and presents it again. If native recovery
fails, matching GOP geometry remains available. The client resources are
revoked at reset, while the display service's software frame and buffer
ownership remain intact. A boot probe also forces a full native reset and
checks that both 2D and VirGL return before starting the display service.

The command layouts follow the
[OASIS VirtIO 1.2 specification](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html).
The texture target, format, and bind values follow Mesa Gallium's
`PIPE_TEXTURE_2D`, `PIPE_FORMAT_B8G8R8A8_UNORM`, and render-target plus
sampler-view flags.

## Validation

- 🟢 `make test-graphics`: capset probe, fenced context lifecycle, texture
  create/upload/destroy command order, submission size rejection, and
  software render-surface contract, including demotion after a failed 3D
  command, context cleanup, and context/texture reconstruction after a
  transient fault.
- 🟢 `make test-virtio-gpu-3d`: GL-backed QEMU device with an explicit render
  node; verifies a context, texture upload, software-to-GPU upload/readback,
  GPU clear/readback, command submission, full device reset, process-scoped
  resource operations, cross-process denial, GPU tile composition, cleanup,
  and a live native 2D display service through serial markers.
- 🟢 `make test-virtio-gpu`: AHCI/NVMe 2D scanout, mode changes, cursor, and
  GOP fallback when the requested mode exceeds native bounds.

QEMU's headless GL display does not expose a screenshot surface to the HMP
`screendump` command in this configuration, so the GL smoke test checks
texture pixels through 3D transfer readback and the live serial session.
Desktop pixels are verified by the ordinary 2D QEMU smoke test.
