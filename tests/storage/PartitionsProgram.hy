using Australis.Kernel.Storage;

public class DiskTransport : IBlockTransport {
    private byte[] disk;
    public DiskTransport(byte[] input) { disk = input; }
    public int SectorSize() { return 512; }
    public long SectorCount() { return disk.Length / 512; }
    public bool Read(long lba, int sectors, byte[] destination) {
        if (lba < 0 || sectors < 1 || lba >= SectorCount() ||
            sectors > SectorCount() - lba || destination.Length < sectors * 512) { return false; }
        int i = 0;
        while (i < sectors * 512) {
            destination[i] = disk[(int)(lba * 512) + i];
            i = i + 1;
        }
        return true;
    }
    public bool Flush() { return true; }
}

public class Program {
    private static void Write32(byte[] bytes, int offset, long value) {
        int i = 0; while (i < 4) { bytes[offset + i] = (byte)(value % 256); value = value / 256; i = i + 1; }
    }
    private static void Write64(byte[] bytes, int offset, long value) {
        int i = 0; while (i < 8) { bytes[offset + i] = (byte)(value % 256); value = value / 256; i = i + 1; }
    }

    private static void Copy(byte[] source, int sourceOffset, byte[] target, int targetOffset, int count) {
        int i = 0;
        while (i < count) { target[targetOffset + i] = source[sourceOffset + i]; i = i + 1; }
    }

    private static void WriteHeader(byte[] disk, int lba, int other, int tableLba, byte[] entries) {
        byte[] header = new byte[512];
        header[0] = 69; header[1] = 70; header[2] = 73; header[3] = 32;
        header[4] = 80; header[5] = 65; header[6] = 82; header[7] = 84;
        Write32(header, 8, 65536); Write32(header, 12, 92);
        Write64(header, 24, lba); Write64(header, 32, other);
        Write64(header, 40, 34); Write64(header, 48, 100);
        Write64(header, 72, tableLba); Write32(header, 80, 5); Write32(header, 84, 128);
        Write32(header, 88, PartitionBytes.Crc32(entries, 0, 640, 640, 0));
        Write32(header, 16, PartitionBytes.Crc32(header, 0, 92, 16, 4));
        Copy(header, 0, disk, lba * 512, 512);
    }

    private static byte[] MakeDisk() {
        byte[] disk = new byte[128 * 512];
        disk[510] = 85; disk[511] = 170; disk[450] = 238;
        Write32(disk, 454, 1); Write32(disk, 458, 127);
        byte[] entries = new byte[1024];
        entries[512] = 40; Write64(entries, 512 + 32, 40); Write64(entries, 512 + 40, 60);
        Copy(entries, 0, disk, 2 * 512, 1024);
        Copy(entries, 0, disk, 125 * 512, 1024);
        WriteHeader(disk, 1, 127, 2, entries);
        WriteHeader(disk, 127, 1, 125, entries);
        return disk;
    }

    public static int Main() {
        byte[] mbr = new byte[512]; mbr[510] = 85; mbr[511] = 170;
        mbr[450] = 238; Write32(mbr, 454, 1); Write32(mbr, 458, 100);
        if (!Mbr.IsValid(mbr) || !Mbr.IsProtective(mbr)) { return 1; }
        Partition protective = Mbr.Entry(mbr, 0);
        if (!protective.Present() || protective.IsGpt() || protective.Type() != 238 || protective.FirstLba() != 1 || protective.BlockCount() != 100) { return 2; }

        byte[] header = new byte[512]; byte[] entries = new byte[128];
        header[0] = 69; header[1] = 70; header[2] = 73; header[3] = 32; header[4] = 80; header[5] = 65; header[6] = 82; header[7] = 84;
        Write32(header, 8, 65536); Write32(header, 12, 92); Write64(header, 24, 1); Write64(header, 32, 999);
        Write64(header, 40, 34); Write64(header, 48, 900); Write64(header, 72, 2); Write32(header, 80, 1); Write32(header, 84, 128);
        entries[0] = 40; Write64(entries, 32, 40); Write64(entries, 40, 99);
        Write32(header, 88, PartitionBytes.Crc32(entries, 0, 128, 128, 0));
        Write32(header, 16, PartitionBytes.Crc32(header, 0, 92, 16, 4));
        if (!Gpt.IsValidHeader(header) || !Gpt.ValidateEntries(header, entries, 128)) { return 3; }
        Partition data = Gpt.Entry(header, entries, 128, 0);
        if (!data.Present() || !data.IsGpt() || data.Type() != 40 || data.FirstLba() != 40 || data.BlockCount() != 60) { return 4; }
        entries[0] = 41;
        if (Gpt.ValidateEntries(header, entries, 128) || Gpt.Entry(header, entries, 128, 0).Present()) { return 5; }

        byte[] disk = MakeDisk();
        GptDisk reader = new GptDisk();
        if (reader.Open(new BlockDevice(new DiskTransport(disk))) != GptDiskStatus.Ok() ||
            reader.UsingBackup() || reader.EntryCount() != 5 || reader.Entry(0).Present()) { return 6; }
        Partition found = reader.FirstPresent();
        if (!found.Present() || found.FirstLba() != 40 || found.BlockCount() != 21 ||
            reader.Entry(4).Type() != 40) { return 7; }
        byte[] matchingType = new byte[16]; matchingType[0] = 40;
        if (reader.FirstWithTypeGuid(matchingType).FirstLba() != 40 || reader.LastStatus() != GptDiskStatus.Ok()) { return 71; }
        matchingType[15] = 1;
        if (reader.FirstWithTypeGuid(matchingType).Present() || reader.LastStatus() != GptDiskStatus.Ok()) { return 72; }
        if (reader.FirstWithTypeGuid(new byte[15]).Present() || reader.LastStatus() != GptDiskStatus.InvalidDevice()) { return 73; }
        if (reader.Entry(5).Present() || reader.LastStatus() != GptDiskStatus.InvalidIndex()) { return 8; }

        disk[1 * 512 + 16] = 0;
        reader = new GptDisk();
        if (reader.Open(new BlockDevice(new DiskTransport(disk))) != GptDiskStatus.Ok() ||
            !reader.UsingBackup() || reader.FirstPresent().FirstLba() != 40) { return 9; }
        disk[127 * 512 + 16] = 0;
        if (new GptDisk().Open(new BlockDevice(new DiskTransport(disk))) != GptDiskStatus.InvalidGpt()) { return 10; }

        disk = MakeDisk();
        disk[2 * 512 + 50] = 1;
        reader = new GptDisk();
        if (reader.Open(new BlockDevice(new DiskTransport(disk))) != GptDiskStatus.Ok() ||
            !reader.UsingBackup()) { return 11; }
        disk = MakeDisk();
        disk[510] = 0;
        if (new GptDisk().Open(new BlockDevice(new DiskTransport(disk))) != GptDiskStatus.InvalidProtectiveMbr()) { return 12; }
        disk = MakeDisk();
        Write64(disk, 1 * 512 + 72, 40);
        Write32(disk, 1 * 512 + 16, PartitionBytes.Crc32(disk, 1 * 512, 92, 16, 4));
        Write64(disk, 127 * 512 + 72, 40);
        Write32(disk, 127 * 512 + 16, PartitionBytes.Crc32(disk, 127 * 512, 92, 16, 4));
        if (new GptDisk().Open(new BlockDevice(new DiskTransport(disk))) != GptDiskStatus.InvalidGpt()) { return 13; }
        System.Console.WriteLine("Australis GPT and MBR parser tests passed");
        return 0;
    }
}
