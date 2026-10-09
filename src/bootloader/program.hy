// Bootloader bring-up checklist (QEMU/OVMF, AHCI and NVMe):
//   [x] Start as the firmware application and report early boot status.
//   [x] Load and validate the separate AUKR kernel image from the boot volume.
//   [x] Capture display and final memory-map information, then leave boot services.
//   [x] Establish a physical allocator, private page tables, null-page guard,
//       bootstrap heap, framebuffer output, CPU tables, and timer interrupt.
//   [x] Emit register-preserving IRQ handlers and retain a KernelBootInfo area
//       for post-handoff device receive rings and allocation diagnostics.
//   [x] Discover PCI storage, map MMIO, reserve DMA pages, and publish GPT data.
//   [x] Switch to a dedicated kernel stack and pass KernelBootInfo to raw code.
//   [x] Boot through the kernel entry on both AHCI and NVMe in QEMU/OVMF.
//   [ ] Exercise missing/corrupt kernel images and handoff failures in QEMU.
//   [ ] Validate the handoff on physical firmware and controller hardware.
//
// Firmware entry and one-way handoff to the raw kernel.

public class Program {
	public static void Main(string[] args) {
		System.Uefi.ClearScreen();
		System.Console.WriteLine("[BOOT] Australis bootloader started.");
		System.Console.WriteLine("[BOOT] Loading raw kernel image.");
		System.Kernel.Boot.Load("\\EFI\\AUSTRALIS\\KERNEL.BIN");
		System.Console.WriteLine("[BOOT] Preparing kernel handoff.");

		// This is the final UEFI boot-service call. After it succeeds, firmware
		// console and driver protocols are no longer available.
		System.Console.WriteLine("[BOOT] Leaving UEFI boot services.");
		System.Uefi.ExitBootServices();

		// Pass a writable KernelBootInfo record in RDI. It contains the final UEFI
		// memory-map values and becomes ready only after the firmware handoff.
		System.Kernel.MemoryMap.Initialize();

		// Use the descriptors to select the largest conventional-memory region
		// and publish the first free physical page plus its allocation limit.
		System.Kernel.Memory.Initialize();

		// Copy every present PML4, PDPT, PD, and PT page into pages from the
		// allocator, then activate that hierarchy through CR3. Leaf mappings
		// retain their existing physical frames and attributes.
		System.Kernel.VirtualMemory.Initialize();

		// Keep virtual address zero unmapped. Large firmware mappings are split
		// only when needed to create that guard page.
		System.Kernel.VirtualMemory.ApplyPolicy();

		// Reserve one zero-filled page and publish its physical address through
		// KernelBootInfo for the next kernel subsystem to consume.
		System.Kernel.Memory.AllocatePage();

		// Build a 16-byte aligned bump heap above the physical allocator. Heap
		// allocation grows the range with zero-filled physical pages as needed.
		System.Kernel.Heap.Initialize();
		System.Kernel.Heap.Allocate(8192);
		System.Kernel.Heap.Allocate(64);

		// This captures GOP data before the firmware handoff, clears the display
		// directly afterwards, and renders each literal through the framebuffer.
		System.Kernel.Framebuffer.Initialize();
		System.Kernel.Framebuffer.WriteLine("[KERNEL] Australis framebuffer console active.");
		System.Kernel.Framebuffer.WriteLine("[KERNEL] Direct pixels after ExitBootServices.");

		// Install ring-0 CPU tables before accepting hardware events. Exceptions
		// record their vector then halt; legacy PIC lines remain masked until a
		// device driver explicitly owns them. The local APIC timer drives the
		// initial monotonic tick counter on vector 0x30.
		System.Kernel.Gdt.Initialize();
		System.Kernel.Idt.Initialize();
		System.Kernel.Interrupts.Initialize();
		System.Kernel.Timer.Initialize();

		// Scan PCI configuration space through 0xcf8/0xcfc. The kernel records
		// the first xHCI, AHCI, and NVMe controllers it finds, maps a guarded
		// 64 KiB uncached register aperture for each, then reserves a disjoint
		// physical DMA range below 4 GiB for controller rings and buffers.
		System.Kernel.Pci.Initialize();
		System.Kernel.Mmio.Initialize();
		System.Kernel.Dma.Initialize();
		// The live AHCI bootstrap reader owns the command list, received-FIS
		// area, command table, and GPT buffer in this contiguous DMA allocation.
		// It validates the MBR, GPT header, and primary entry array before it
		// publishes the first GPT partition in KernelBootInfo.
		System.Kernel.Dma.AllocatePages(16);
		System.Kernel.Storage.Initialize();
		// Switch to the kernel's own stack and enter the raw code image.
		// The kernel enables interrupts and owns the idle loop from here.
		System.Kernel.Runtime.Execute();
	}
}
