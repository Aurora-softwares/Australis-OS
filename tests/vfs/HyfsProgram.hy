using Australis.Kernel.Storage;
using Australis.Kernel.Vfs;

public class MemoryTransport : IBlockTransport {
    private byte[] image;
    private bool failReads;
    private int reads;

    public MemoryTransport(byte[] inputImage) {
        image = inputImage;
        failReads = false;
        reads = 0;
    }

    public int SectorSize() { return 512; }
    public long SectorCount() { return image.Length / 512; }
    public bool Read(long lba, int sectors, byte[] destination) {
        reads = reads + 1;
        if (failReads || lba < 0 || sectors < 1 || lba >= SectorCount() || sectors > SectorCount() - lba ||
            destination.Length < sectors * 512) { return false; }
        int source = (int)(lba * 512);
        int length = sectors * 512;
        int i = 0;
        while (i < length) { destination[i] = image[source + i]; i = i + 1; }
        return true;
    }
    public bool Flush() { return true; }
    public void SetFailReads(bool value) { failReads = value; }
    public int Reads() { return reads; }
}

public class Program {
    private static void Write32(byte[] bytes, int offset, long value) {
        int i = 0;
        while (i < 4) { bytes[offset + i] = (byte)(value % 256); value = value / 256; i = i + 1; }
    }

    private static void Write64(byte[] bytes, int offset, long value) {
        int i = 0;
        while (i < 8) { bytes[offset + i] = (byte)(value % 256); value = value / 256; i = i + 1; }
    }

    private static void Copy(byte[] source, int sourceOffset, byte[] target, int targetOffset, int length) {
        int i = 0;
        while (i < length) { target[targetOffset + i] = source[sourceOffset + i]; i = i + 1; }
    }

    private static void WriteName(byte[] directory, int offset, string name) {
        int i = 0;
        while (i < name.Length) {
            string c = name[i];
            if (c == "b") { directory[offset + 24 + i] = 98; }
            if (c == "o") { directory[offset + 24 + i] = 111; }
            if (c == "t") { directory[offset + 24 + i] = 116; }
            if (c == ".") { directory[offset + 24 + i] = 46; }
            if (c == "x") { directory[offset + 24 + i] = 120; }
            if (c == "e") { directory[offset + 24 + i] = 101; }
            if (c == "m") { directory[offset + 24 + i] = 109; }
            if (c == "p") { directory[offset + 24 + i] = 112; }
            if (c == "y") { directory[offset + 24 + i] = 121; }
            i = i + 1;
        }
    }

    // Build a complete 32-sector HyFS volume at LBA 8 in a 64-sector disk.
    // The file payload is stored at filesystem block 2, after the superblock
    // and its one-sector directory table.
    private static byte[] MakeImage() {
        byte[] image = new byte[64 * 512];
        byte[] superblock = new byte[512];
        byte[] directory = new byte[512];
        byte[] content = new byte[5];
        content[0] = 104; content[1] = 101; content[2] = 108; content[3] = 108; content[4] = 111;

        superblock[0] = 72; superblock[1] = 89; superblock[2] = 70; superblock[3] = 83;
        superblock[4] = 13; superblock[5] = 10; superblock[6] = 26; superblock[7] = 10;
        Write32(superblock, 8, 1); Write32(superblock, 12, 512); Write64(superblock, 16, 32);
        Write64(superblock, 24, 1); Write32(superblock, 32, 1); Write32(superblock, 36, 2);

        directory[0] = 8; directory[1] = 1; Write64(directory, 4, 2); Write64(directory, 12, 5);
        Write32(directory, 20, PartitionBytes.Crc32(content, 0, 5, 5, 0)); WriteName(directory, 0, "boot.txt");
        directory[64] = 9; directory[65] = 1; Write64(directory, 68, 0); Write64(directory, 76, 0);
        Write32(directory, 84, 0); WriteName(directory, 64, "empty.txt");

        Write32(superblock, 40, PartitionBytes.Crc32(directory, 0, 512, 512, 0));
        Write32(superblock, 44, PartitionBytes.Crc32(superblock, 0, 48, 44, 4));
        Copy(superblock, 0, image, 8 * 512, 512);
        Copy(directory, 0, image, 9 * 512, 512);
        Copy(content, 0, image, 10 * 512, 5);
        return image;
    }

    // A file larger than the former 1 MiB limit also crosses a sector edge
    // at the requested slice. Reading it must need only a small scratch buffer.
    private static byte[] MakeLargeImage() {
        int fileLength = 1048577;
        byte[] image = new byte[2060 * 512];
        byte[] superblock = new byte[512];
        byte[] directory = new byte[512];
        byte[] content = new byte[fileLength];
        content[511] = 17; content[512] = 18; content[513] = 19;

        superblock[0] = 72; superblock[1] = 89; superblock[2] = 70; superblock[3] = 83;
        superblock[4] = 13; superblock[5] = 10; superblock[6] = 26; superblock[7] = 10;
        Write32(superblock, 8, 1); Write32(superblock, 12, 512); Write64(superblock, 16, 2052);
        Write64(superblock, 24, 1); Write32(superblock, 32, 1); Write32(superblock, 36, 1);
        directory[0] = 8; directory[1] = 1; Write64(directory, 4, 2);
        Write64(directory, 12, fileLength);
        Write32(directory, 20, PartitionBytes.Crc32(content, 0, fileLength, fileLength, 0));
        WriteName(directory, 0, "boot.txt");
        Write32(superblock, 40, PartitionBytes.Crc32(directory, 0, 512, 512, 0));
        Write32(superblock, 44, PartitionBytes.Crc32(superblock, 0, 48, 44, 4));
        Copy(superblock, 0, image, 8 * 512, 512);
        Copy(directory, 0, image, 9 * 512, 512);
        Copy(content, 0, image, 10 * 512, fileLength);
        return image;
    }

    public static int Main() {
        byte[] image = MakeImage();
        MemoryTransport transport = new MemoryTransport(image);
        BlockDevice device = new BlockDevice(transport);
        Partition root = new Partition(true, true, 0, 8, 32);
        Hyfs hyfs = new Hyfs();

        if (hyfs.Mount(device, root) != VfsStatus.Ok() || !hyfs.IsMounted()) { return 1; }
        if (!hyfs.Exists("/boot.txt") || !hyfs.Exists("/empty.txt") || hyfs.Exists("/missing") || hyfs.Exists("/bad/name")) { return 2; }
        if (hyfs.Stat("/boot.txt").ByteLength() != 5 || !hyfs.Stat("/empty.txt").Exists() ||
            hyfs.Stat("/empty.txt").ByteLength() != 0 || hyfs.Stat("/missing").Status() != VfsStatus.NotFound()) { return 3; }

        byte[] partial = new byte[3];
        if (hyfs.ReadFile("/boot.txt", 1, partial) != VfsStatus.Ok() || partial[0] != 101 || partial[1] != 108 || partial[2] != 108) { return 4; }
        if (hyfs.ReadFile("/boot.txt", 4, new byte[2]) != VfsStatus.EndOfFile() ||
            hyfs.ReadFile("/missing", 0, new byte[1]) != VfsStatus.NotFound() ||
            hyfs.ReadFile("/empty.txt", 0, new byte[0]) != VfsStatus.Ok()) { return 5; }

        Vfs vfs = new Vfs();
        if (vfs.MountRoot(hyfs, device, root) != VfsStatus.Ok() || vfs.StatRootFile("/boot.txt").ByteLength() != 5) { return 6; }
        byte[] full = new byte[5];
        if (vfs.ReadRootFile("/boot.txt", 0, full) != VfsStatus.Ok() || full[0] != 104 || full[4] != 111) { return 7; }
        byte[] name = new byte[32];
        if (vfs.RootDirectorySlotCount() != 2 || vfs.CopyRootDirectoryEntryName(0, name) != 8 ||
            name[0] != 98 || name[7] != 116 || vfs.CopyRootDirectoryEntryName(1, name) != 9 ||
            name[0] != 101 || name[8] != 116) { return 71; }

        // The data CRC is checked before any caller-visible bytes are copied.
        image[10 * 512] = 72;
        byte[] unchanged = new byte[2]; unchanged[0] = 91; unchanged[1] = 92;
        if (hyfs.ReadFile("/boot.txt", 0, unchanged) != VfsStatus.Corrupt() || unchanged[0] != 91 || unchanged[1] != 92) { return 8; }

        byte[] invalid = MakeImage();
        invalid[8 * 512] = 88;
        if (new Hyfs().Mount(new BlockDevice(new MemoryTransport(invalid)), root) != VfsStatus.MountFailed()) { return 9; }

        byte[] corruptDirectory = MakeImage();
        corruptDirectory[9 * 512 + 24] = 66;
        if (new Hyfs().Mount(new BlockDevice(new MemoryTransport(corruptDirectory)), root) != VfsStatus.MountFailed()) { return 91; }

        MemoryTransport failedTransport = new MemoryTransport(MakeImage());
        failedTransport.SetFailReads(true);
        if (new Hyfs().Mount(new BlockDevice(failedTransport), root) != VfsStatus.IoFailure()) { return 10; }

        byte[] largeImage = MakeLargeImage();
        Partition largeRoot = new Partition(true, true, 0, 8, 2052);
        MemoryTransport largeTransport = new MemoryTransport(largeImage);
        Hyfs largeHyfs = new Hyfs();
        if (largeHyfs.Mount(new BlockDevice(largeTransport), largeRoot) != VfsStatus.Ok() ||
            largeHyfs.Stat("/boot.txt").ByteLength() != 1048577) { return 11; }
        byte[] crossSector = new byte[3];
        if (largeHyfs.ReadFile("/boot.txt", 511, crossSector) != VfsStatus.Ok() ||
            crossSector[0] != 17 || crossSector[1] != 18 || crossSector[2] != 19) { return 12; }
        largeImage[10 * 512 + 1000] = 1;
        crossSector[0] = 91; crossSector[1] = 92; crossSector[2] = 93;
        if (largeHyfs.ReadFile("/boot.txt", 511, crossSector) != VfsStatus.Corrupt() ||
            crossSector[0] != 91 || crossSector[1] != 92 || crossSector[2] != 93) { return 13; }

        System.Console.WriteLine("Australis HyFS tests passed");
        return 0;
    }
}
