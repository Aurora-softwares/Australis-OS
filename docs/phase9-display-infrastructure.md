# Phase 9 display infrastructure

The display lease now uses `IDisplayBackend` for output. `GopDisplayBackend`
owns the firmware framebuffer mapping and pixel conversion; `DisplayDevice`
holds only the backend interface. A native backend can implement the same
contract without giving the compositor or a client GOP addresses. The
interface reports kind, geometry, scanout stride and format, and capability
bits for partial damage, immediate writes, synchronous completion, and an
optional hardware cursor.

`DisplayBufferLayout` validates a logical RGBX8888 buffer separately from
the scanout format. Width and height are bounded by 2048, the pixel count by
1,048,576, and byte length by 8 MiB. Stride must be four-byte aligned and
at least four bytes per pixel. The current compositor backbuffer remains
tightly packed; presentation translates to the backend's scanout format.

`DisplayDevice` initializes its backend at creation, releases the display
lease on shutdown, and can recover an unowned backend. It keeps an open
frame on a failed presentation so the caller may retry. Automatic recovery
rejects a changed geometry while an existing backbuffer or pooled presentation
buffer still has the old dimensions. Phase 10 adds an explicit native mode
change path that revokes buffer handles and reshapes the retained storage.
The host graphics test exercises the same device with GOP and a simulated
native backend, including failed presentation and shutdown/recovery.

## Owned presentation buffers

The AUEX display owner may allocate up to three full-screen, tightly packed
RGBX8888 buffers. Allocation validates dimensions, format, stride, and the
layout limits before storage is made available. Buffers are kernel-owned and
identified by monotonically increasing handles; neither an application nor
the compositor receives a framebuffer or kernel address. The slots retain
their bounded storage for reuse after `DestroyBuffer`, but clear all pixels,
damage, fence state, and ownership before a new handle is assigned. Lease
release, process exit, and backend shutdown revoke all handles.

Each buffer follows `available → drawing → submitted → available`.
`BeginBuffer` opens a free buffer, `FillBufferRect` validates and tracks its
damage, and `SubmitBuffer` returns a positive completion fence only after
the backend accepts the frame. A failed submission leaves the buffer in the
drawing state for retry. `BufferCompletion(handle, fence)` reports `1` once
the exact submission has completed; `ReleaseBuffer` requires that same fence
before the buffer can be drawn again or destroyed. The GOP backend completes
synchronously, so its fence is already signalled when submission returns.
These calls establish the contract for a future asynchronous native backend.

The live display service submits two distinct buffers during boot and checks
their fences and release order before drawing the desktop. The two ordinary
client processes attempt all buffer calls and receive `-13` because they do
not hold the display capability or lease. Host tests additionally cover
allocation limits, cross-process handles, stale handles, failed submissions,
and revocation after owner exit.

## Status

- 🟢 Backend interface and GOP implementation.
- 🟢 Buffer layout and output capability contracts.
- 🟢 GOP lifecycle and recovery contract; the Phase 10 native backend now
  implements reset and resource recreation through this interface.
- 🟢 Pollable submission fences, owned allocation, isolation, explicit release,
  and three bounded presentation buffer slots.

Validation: `make test-graphics`, `make test-stage5-host`, `make build`,
`make iso-hyfs2`, and AHCI/NVMe QEMU display tests. The resize gesture in the
desktop smoke test holds the mouse button across separate USB reports so an
emulated redraw cannot merge the press with the later release.
