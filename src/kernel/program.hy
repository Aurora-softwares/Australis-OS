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

		// System.Console uses the UEFI text console, so output must stop here.
		// Halt is a safe temporary kernel loop until an independent runtime exists.
		//
		// Next kernel milestones:
		// [x] Pass the captured memory map through KernelBootInfo.
		// [x] Initialize the physical-page allocator from the memory map.
		// [x] Activate an allocator-owned paging hierarchy with current mappings.
		// [x] Guard virtual page zero and expose zero-filled page allocation.
		// [x] Add a page-backed, 16-byte aligned bump heap allocator.
		// [x] Framebuffer console.
		// [ ] GDT, IDT, exception handlers, interrupts, and timer.
		// [ ] PCI enumeration and NVMe/AHCI storage drivers.
		// [ ] Block-device layer and GPT/MBR partition support.
		// [ ] VFS plus an initial HyFS driver.
		// [ ] Mount HyFS as the root filesystem.
		// [ ] Add FAT/FAT32 support, then NTFS support.
		// [ ] Add USB controller and USB mass-storage drivers.
		// [ ] Add a Hydrogen program loader and an initial shell.
		// [ ] Add scheduling, processes, user space, and system calls.

		System.Kernel.Halt();
	}
}
