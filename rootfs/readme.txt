Australis boots a separate freestanding kernel image after its firmware loader has
captured the memory map, left boot services, and prepared the kernel handoff.
The kernel chooses this HyFS root by its full GPT partition type identifier.
Its AHCI and NVMe block transports both read the same partition through the
BlockDevice interface, and the VFS mounts the read-only HyFS driver over it.
Each file read checks the stored data checksum before the bytes are returned.

This fixture intentionally crosses a logical-sector boundary. Reading it from
both emulated controllers exercises more than the superblock and directory:
the kernel must fetch several data sectors, validate the full file, and publish
the resulting length and checksum in its boot diagnostics. Future shell work
can use the mounted VFS to open files and display their contents at a prompt.
