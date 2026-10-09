// Freestanding kernel bring-up checklist (QEMU/OVMF, AHCI and NVMe):
//   [x] Enter separate position-independent raw code on the kernel stack.
//   [x] Validate KernelBootInfo and allocate a zeroed physical page.
//   [x] Run page-backed object, array, and string allocation after handoff.
//   [x] Reinitialize a live AHCI or NVMe controller through kernel MMIO/DMA.
//   [x] Read sectors through BlockDevice and validate GPT through GptDisk.
//   [x] Publish a ready state, enable interrupts, and own the idle loop.
//   [x] Verify the complete entry and storage path in both QEMU boot tests.
//   [x] Keep host-tested VFS, read-only HyFS, and USB protocol modules in source.
//   [x] Select the HyFS GPT type, mount a live root, and read checked files
//       through the VFS on both AHCI and NVMe, including multiple sectors.
//   [x] Bring up COM1 after handoff and run an interactive kernel shell with
//       bounded line editing, help, echo, ls, cat, and version over serial.
//   [x] Protect persistent kernel allocations from shell temporaries, record
//       allocation faults, and wake COM1 input through a PIC IRQ handler.
//   [x] Reuse freed physical pages and map/unmap explicit 4 KiB kernel pages
//       with a local TLB invalidation after every mapping transition.
//   [ ] Add reusable file handles and nested directory traversal to the VFS.
//   [ ] Add FAT/FAT32 and NTFS drivers if those volumes become boot requirements.
//   [ ] Add general allocation/free, dynamic mappings, and bounded recovery
//       for faults beyond the shell's scoped transient allocation region.
//   [ ] Add device IRQ handling beyond COM1 to kernel drivers.
//   [ ] Bring up xHCI, USB devices, HID input, and mass storage on live hardware.
//   [ ] Add an executable format and program loader.
//   [ ] Add threads, scheduling, processes, privilege separation, system calls,
//       a user-space runtime, and an initial user-space shell.
//
// This method graph is compiled as position-independent freestanding x86-64
// code. The handoff passes the writable KernelBootInfo address as a long.
public class KernelCounter {
    private int value;

    public KernelCounter(int initial) { value = initial; }
    public int Value() { return value; }
}

public class KernelMain {
    private static byte[] HyfsTypeGuid() {
        // GPT stores the first three GUID fields in little-endian order.
        // 9f5eb82e-692e-5a8f-b968-adaaa349dd93
        byte[] guid = new byte[16];
        guid[0] = 46; guid[1] = 184; guid[2] = 94; guid[3] = 159;
        guid[4] = 46; guid[5] = 105; guid[6] = 143; guid[7] = 90;
        guid[8] = 185; guid[9] = 104; guid[10] = 173; guid[11] = 170;
        guid[12] = 163; guid[13] = 73; guid[14] = 221; guid[15] = 147;
        return guid;
    }

    private static int ValidateBootInfo(long bootInfo) {
        if (bootInfo < 4096) { return 1; }
        if (System.Kernel.Memory.Read32(bootInfo) != 1229083969) { return 2; }
        if (System.Kernel.Memory.Read32(bootInfo + 4) != 7) { return 3; }
        return 0;
    }

    public static int Run(long bootInfo) {
        int headerStatus = ValidateBootInfo(bootInfo);
        if (headerStatus != 0) { return headerStatus; }
        if (!KernelAddressSpace.Validate(bootInfo)) {
            System.Kernel.Memory.Write32(bootInfo + 1164, 1);
            return 21;
        }
        if (System.Kernel.Memory.Read32(bootInfo + 36) != 131071) { return 4; }
        if (System.Kernel.Memory.Read32(bootInfo + 304) == 0) { return 5; }
        if (System.Kernel.Memory.Read32(bootInfo + 316) != 512) { return 6; }
        if (System.Kernel.Memory.Read64(bootInfo + 384) == 0) { return 7; }
        long page = PhysicalPages.AllocateZeroed(bootInfo);
        if (page == 0 || System.Kernel.Memory.Read64(page + 8) != 0) { return 8; }
        System.Kernel.Memory.Write64(bootInfo + 480, page);
        System.Kernel.Memory.Write64(page + 8, 123456789);
        // Exercise the post-handoff ownership contract before managed runtime
        // allocations begin. The page is unmapped before it is returned to the
        // free pool, so later object allocation cannot retain a stale mapping.
        long mappingPage = PhysicalPages.AllocateZeroed(bootInfo);
        // Select a lower canonical PML4 slot outside the bootstrap identity
        // aperture, whose large leaves this API will not split.
        long mappingAddress = KernelAddressSpace.FindUnmappedPml4Base(bootInfo);
        if (mappingAddress == 0) { System.Kernel.Memory.Write32(bootInfo + 1200, 7); return 22; }
        if (mappingPage == 0) { System.Kernel.Memory.Write32(bootInfo + 1200, 1); return 22; }
        if (!KernelAddressSpace.MapPage(bootInfo, mappingAddress, mappingPage, KernelAddressSpace.ReadWrite())) {
            System.Kernel.Memory.Write32(bootInfo + 1200, 2); return 22;
        }
        if (KernelAddressSpace.Translate(bootInfo, mappingAddress) != mappingPage) {
            System.Kernel.Memory.Write32(bootInfo + 1200, 3); return 22;
        }
        if (KernelAddressSpace.IsExecutable(bootInfo, mappingAddress)) {
            System.Kernel.Memory.Write32(bootInfo + 1200, 10); return 22;
        }
        if (!KernelAddressSpace.UnmapPage(bootInfo, mappingAddress)) {
            System.Kernel.Memory.Write32(bootInfo + 1200, 4); return 22;
        }
        if (KernelAddressSpace.Translate(bootInfo, mappingAddress) != 0) {
            System.Kernel.Memory.Write32(bootInfo + 1200, 5); return 22;
        }
        if (!PhysicalPages.Free(bootInfo, mappingPage)) {
            System.Kernel.Memory.Write32(bootInfo + 1200, 6); return 22;
        }
        // A duplicate free must be rejected, and the next allocation must
        // return the original page after clearing its diagnostic state.
        if (PhysicalPages.Free(bootInfo, mappingPage)) {
            System.Kernel.Memory.Write32(bootInfo + 1200, 8); return 22;
        }
        long reusedPage = PhysicalPages.AllocateZeroed(bootInfo);
        if (reusedPage != mappingPage || !PhysicalPages.Free(bootInfo, reusedPage)) {
            System.Kernel.Memory.Write32(bootInfo + 1200, 9); return 22;
        }
        byte[] scratch = new byte[16];
        scratch[0] = 42;
        scratch[15] = 99;
        if (scratch.Length != 16 || scratch[0] != 42 || scratch[15] != 99) { return 9; }
        KernelCounter counter = new KernelCounter(57);
        if (counter.Value() != 57) { return 10; }
        string greeting = "Australis";
        if (greeting.Length != 9) { return 11; }
        System.Kernel.Memory.Write32(bootInfo + 496, 0);
        Australis.Kernel.Storage.BlockDevice disk = null;
        if (System.Kernel.Memory.Read32(bootInfo + 304) == 2) {
            Australis.Kernel.Storage.NativeNvmeIo io = new Australis.Kernel.Storage.NativeNvmeIo(bootInfo);
            Australis.Kernel.Storage.NvmeController controller = new Australis.Kernel.Storage.NvmeController(io, 5000000);
            if (!controller.Initialize()) { return 12; }
            disk = new Australis.Kernel.Storage.BlockDevice(controller);
            byte[] gptHeader = new byte[512];
            if (disk.Read(1, 1, gptHeader) != 0) { return 13; }
            if (gptHeader[0] != 69 || gptHeader[1] != 70 || gptHeader[2] != 73 ||
                gptHeader[3] != 32 || gptHeader[4] != 80 || gptHeader[5] != 65 ||
                gptHeader[6] != 82 || gptHeader[7] != 84) { return 14; }
            System.Kernel.Memory.Write32(bootInfo + 496, 1);
        } else {
            Australis.Kernel.Storage.NativeAhciIo io = new Australis.Kernel.Storage.NativeAhciIo(bootInfo);
            Australis.Kernel.Storage.AhciController controller = new Australis.Kernel.Storage.AhciController(io, 1000000);
            if (!controller.Initialize()) { return 17; }
            disk = new Australis.Kernel.Storage.BlockDevice(controller);
            byte[] ahciHeader = new byte[512];
            if (disk.Read(1, 1, ahciHeader) != 0 || ahciHeader[0] != 69 || controller.LastError() != 0) { return 18; }
        }
        Australis.Kernel.Storage.GptDisk gpt = new Australis.Kernel.Storage.GptDisk();
        int gptStatus = gpt.Open(disk);
        System.Kernel.Memory.Write32(bootInfo + 504, gptStatus);
        System.Kernel.Memory.Write32(bootInfo + 508, disk.LastStatus());
        if (gptStatus != 0) { return 15; }
        Australis.Kernel.Storage.Partition partition = gpt.FirstPresent();
        if (!partition.Present() || partition.FirstLba() != System.Kernel.Memory.Read64(bootInfo + 376) ||
            partition.BlockCount() != System.Kernel.Memory.Read64(bootInfo + 384)) { return 16; }
        System.Kernel.Memory.Write32(bootInfo + 500, 1);

        Australis.Kernel.Storage.Partition root = gpt.FirstWithTypeGuid(HyfsTypeGuid());
        if (gpt.LastStatus() != Australis.Kernel.Storage.GptDiskStatus.Ok() || !root.Present()) { return 19; }
        System.Kernel.Memory.Write64(bootInfo + 1096, root.FirstLba());
        System.Kernel.Memory.Write64(bootInfo + 1104, root.BlockCount());
        Australis.Kernel.Vfs.Vfs vfs = new Australis.Kernel.Vfs.Vfs();
        int mountStatus = vfs.MountRoot(new Australis.Kernel.Vfs.Hyfs(), disk, root);
        System.Kernel.Memory.Write32(bootInfo + 1076, mountStatus);
        if (mountStatus != Australis.Kernel.Vfs.VfsStatus.Ok() || !vfs.IsRootMounted()) { return 20; }
        int rootState = 1;
        System.Kernel.Memory.Write32(bootInfo + 1072, rootState);

        // These bounded reads publish diagnostics for the boot image. A valid
        // root with different files remains bootable; QEMU verifies both
        // fixture files and their complete checksums separately.
        Australis.Kernel.Vfs.VfsFileInfo helloInfo = vfs.StatRootFile("/hello.txt");
        if (helloInfo.Exists() && helloInfo.ByteLength() <= 2048) {
            byte[] hello = new byte[(int)helloInfo.ByteLength()];
            int readStatus = vfs.ReadRootFile("/hello.txt", 0, hello);
            System.Kernel.Memory.Write32(bootInfo + 1112, readStatus);
            if (readStatus == Australis.Kernel.Vfs.VfsStatus.Ok()) {
                System.Kernel.Memory.Write64(bootInfo + 1080, helloInfo.ByteLength());
                System.Kernel.Memory.Write64(bootInfo + 1088,
                    Australis.Kernel.Storage.PartitionBytes.Crc32(hello, 0, hello.Length, hello.Length, 0));
                rootState = rootState + 2;
            }
        }

        Australis.Kernel.Vfs.VfsFileInfo readmeInfo = vfs.StatRootFile("/readme.txt");
        if (readmeInfo.Exists() && readmeInfo.ByteLength() <= 2048) {
            byte[] readme = new byte[(int)readmeInfo.ByteLength()];
            int readmeStatus = vfs.ReadRootFile("/readme.txt", 0, readme);
            System.Kernel.Memory.Write32(bootInfo + 1136, readmeStatus);
            if (readmeStatus == Australis.Kernel.Vfs.VfsStatus.Ok()) {
                System.Kernel.Memory.Write64(bootInfo + 1120, readmeInfo.ByteLength());
                System.Kernel.Memory.Write64(bootInfo + 1128,
                    Australis.Kernel.Storage.PartitionBytes.Crc32(readme, 0, readme.Length, readme.Length, 0));
                rootState = rootState + 4;
            }
        }
        System.Kernel.Memory.Write32(bootInfo + 1072, rootState);

        System.Kernel.Memory.Write32(bootInfo + 488, scratch[0] + counter.Value());
        System.Kernel.Memory.Write32(bootInfo + 492, greeting.Length);
        System.Kernel.Memory.Write32(bootInfo + 472, 1);
        System.Kernel.Memory.Write32(bootInfo + 36, 262143);
        Australis.Kernel.Console.SerialPort serial = new Australis.Kernel.Console.SerialPort(1016, bootInfo);
        bool serialReady = serial.Initialize();
        if (serialReady) {
            int serialFlags = 1;
            if (serial.ReceiveInterruptsEnabled()) { serialFlags = serialFlags + 2; }
            System.Kernel.Memory.Write32(bootInfo + 1140, serialFlags);
        }
        System.Kernel.Cpu.EnableInterrupts();
        if (serialReady) {
            Australis.Kernel.Console.SerialShell shell =
                new Australis.Kernel.Console.SerialShell(serial, vfs, bootInfo);
            shell.Run();
        }
        while (true) { System.Kernel.Cpu.Halt(); }
        return 0;
    }
}
