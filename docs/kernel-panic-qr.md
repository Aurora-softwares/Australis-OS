# Kernel panic QR diagnostics

Australis prints the full CPU panic report to serial and the firmware
framebuffer. It also encodes a compact report as a Version 3-L QR code with a
four-module quiet zone. The fixed payload is
`AU1:VV:EEEEEEEEEEEEEEEE:RRRRRRRRRRRRRRRR:SSSSSSSSSSSSSSSS:CCCCCCCCCCCCCCCC`,
where `VV` is the exception vector and the four 16-digit fields are the error
code, RIP, RSP, and CR2. The text remains the complete diagnostic record.

The kernel reserves the QR scratch page and a 16 KiB emergency stack before
normal work begins. The panic path does not allocate memory. It renders text
first, then the QR. When native VirtIO-GPU owns the display, it copies the
panic text into the existing scanout backing, draws the QR at that mode's
right edge, and submits one bounded transfer and flush through the already
allocated control queue. If the GPU queue is unavailable or busy, the serial
report and the generated QR data remain available; visible GPU output is
best effort. GOP output is available when the firmware framebuffer is the
active display.

`make test-kernel-panic` triggers page and general-protection faults on both
GOP and native VirtIO-GPU boots. It compares the rendered pixels against the
kernel's QR matrix and uses `zbarimg` to decode each actual QEMU screenshot.
The debug boot self-test separately checks the QR encoder without causing a
panic. Faults before the scratch page and emergency stack are installed, or
on a display too small for the panic text and QR, can still only rely on the
serial report.
