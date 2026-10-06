public class Program {
    public static void Main(string[] args) {
		//
		// Bridge the gap between UEFI and the kernel.
		//
		// This is a temporary solution until the kernel is fully implemented.
		// The bootloader will load the kernel and then transfer control to it.
		// The kernel will then take over and continue the boot process.
		//
		System.Console.WriteLine("[BOOT] Hydrogen Bootloader");
		System.Console.WriteLine("[BOOT] Loading EFI kernel...");

		//
		// Place the kernel's sections at the right addresses,
		// apply relocations if needed,
		// gather boot info,
		// then call ExitBootServices and jump to the kernel's entry point
		//

		//
		// load the kernel image at the end of your own loader code,
		// you do a normal CPU jump to the kernel's entry address
		//

		System.Uefi.StartImage("\\EFI\\AUSTRALIS\\KERNEL.EFI");
    }
}
