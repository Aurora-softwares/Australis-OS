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

        // Clone the active PML4 into a page from the new allocator, then load
        // that kernel-owned root into CR3 while retaining the current mappings.
        System.Kernel.VirtualMemory.Initialize();

        // System.Console uses the UEFI text console, so output must stop here.
        // Halt is a safe temporary kernel loop until an independent runtime exists.
        //
        // Next kernel milestones:
        // [x] Pass the captured memory map through KernelBootInfo.
        // [x] Initialize the physical-page allocator from the memory map.
        // [x] Activate a kernel-owned PML4 with the current mappings.
        // [ ] Replace inherited lower-level mappings with kernel page tables.
        // [ ] Add a kernel heap allocator above the physical-page allocator.
        // [ ] Add a framebuffer console, then GDT, IDT, interrupts, and a timer.
        // [ ] Enumerate PCI devices and add storage, USB, and filesystem drivers.
        // [ ] Add scheduling, processes, user space, and system calls.

        System.Kernel.Halt();
    }
}
