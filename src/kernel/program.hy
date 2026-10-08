// Next kernel milestones:
//	[x] Activate an allocator-owned paging hierarchy with current mappings.
//	[x] Guard virtual page zero and expose zero-filled page allocation.
//	[x] Add a page-backed, 16-byte aligned bump heap allocator.
//
//	[x] Boot information / memory map
//	[x] Physical memory manager
//	[x] Virtual memory manager
//	[x] Null-page guard
//	[x] Zero-page allocation
//	[x] Kernel heap
//	[x] Framebuffer console
//
//	[x] GDT
//	[x] IDT
//	[x] Exception handlers
//	[x] Interrupt controller (APIC/PIC)
//	[x] Timer tick counter and IRQ dispatch
//
//	[x] PCI enumeration through configuration-space port I/O
//	[x] Fixed high MMIO register apertures for discovered xHCI, AHCI, and NVMe controllers
//	[x] Contiguous, zero-filled DMA allocation below 4 GiB
//	[x] Host-tested block-device abstraction
//	[x] Host-tested AHCI/SATA command and identify protocol
//	[x] Host-tested NVMe command and namespace protocol
//
//	[x] Live AHCI reads of the MBR, GPT header, and bounded primary GPT entry array
//	[x] CRC-checked GPT parser and protective MBR parser
//	[ ] Live NVMe transport code in the freestanding kernel
//
//	[x] Host-tested VFS interface and root-mount contract
//	[ ] HyFS driver
//	[ ] Mount root filesystem - HyFS
//
//	[ ] FAT/FAT32 driver
//	[ ] NTFS driver
//
//	[ ] USB host-controller support
//	[ ] USB device enumeration
//	[ ] USB mass-storage support
//
//	[ ] Hydrogen executable/program format
//	[ ] Hydrogen program loader
//	[ ] Kernel shell
//
//	[ ] Thread abstraction
//	[ ] Scheduler
//	[ ] Processes
//	[ ] User/kernel privilege separation
//	[ ] System-call ABI
//	[ ] User-space runtime
//	[ ] Initial user-space shell

public class Program {
	public static void Main(string[] args) {
		System.Console.WriteLine("[KERNEL] Australis kernel started.");
		System.Console.WriteLine("[KERNEL] Capturing UEFI memory map.");
		System.Console.WriteLine("[KERNEL] Preparing physical memory.");
		System.Console.WriteLine("[KERNEL] Preparing virtual memory.");

		// This is the final UEFI boot-service call. After it succeeds, firmware
		// console and driver protocols are no longer available.
		System.Console.WriteLine("[KERNEL] Leaving UEFI boot services.");
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
		System.Kernel.Interrupts.Enable();
		System.Kernel.Interrupts.Idle();
	}
}
