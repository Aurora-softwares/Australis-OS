using Australis.Kernel.Storage;

public class MockBlockTransport : IBlockTransport {
    private bool failRead;
    private bool failFlush;
    private bool failWrite;
    private int calls;
    private int writeCalls;
    private int writtenByte;

    public MockBlockTransport(bool inputFailRead, bool inputFailFlush) {
        failRead = inputFailRead;
        failFlush = inputFailFlush;
        failWrite = false;
        calls = 0; writeCalls = 0; writtenByte = -1;
    }

    public int SectorSize() { return 512; }
    public long SectorCount() { return 64; }
    public bool Read(long lba, int sectors, byte[] destination) {
        calls = calls + 1;
        int i = 0;
        while (i < sectors * 512) { destination[i] = (byte)(lba + i); i = i + 1; }
        return !failRead;
    }
    public bool Flush() { return !failFlush; }
    public bool Write(long lba, int sectors, byte[] source) {
        writeCalls = writeCalls + 1;
        writtenByte = source[0];
        source[0] = 0;
        return !failWrite;
    }
    public int Calls() { return calls; }
    public int WriteCalls() { return writeCalls; }
    public int WrittenByte() { return writtenByte; }
    public void SetFailWrite(bool value) { failWrite = value; }
}

public class InvalidBlockTransport : IBlockTransport {
    public int SectorSize() { return 768; }
    public long SectorCount() { return 8; }
    public bool Read(long lba, int sectors, byte[] destination) { return true; }
    public bool Write(long lba, int sectors, byte[] source) { return true; }
    public bool Flush() { return true; }
}

public class Program {
    public static int Main() {
        MockBlockTransport transport = new MockBlockTransport(false, false);
        BlockDevice disk = new BlockDevice(transport);
        if (disk.SectorSize() != 512 || disk.SectorCount() != 64) { return 1; }
        byte[] sector = new byte[512];
        if (disk.Read(63, 1, sector) != BlockStatus.Ok() || sector[0] != 63 || transport.Calls() != 1) { return 2; }
        if (disk.Read(64, 1, sector) != BlockStatus.OutOfRange() || transport.Calls() != 1) { return 3; }
        if (disk.Read(63, 2, new byte[1024]) != BlockStatus.OutOfRange() || transport.Calls() != 1) { return 4; }
        if (disk.Read(0, 2, sector) != BlockStatus.InvalidArgument() || transport.Calls() != 1) { return 5; }
        if (disk.Flush() != BlockStatus.Ok()) { return 6; }
        byte[] source = new byte[512]; source[0] = 77;
        if (disk.Write(2, 1, source) != BlockStatus.Ok() ||
            transport.WriteCalls() != 1 || transport.WrittenByte() != 77 ||
            source[0] != 77) { return 11; }
        if (disk.Write(64, 1, source) != BlockStatus.OutOfRange() ||
            disk.Write(0, 2, source) != BlockStatus.InvalidArgument() ||
            transport.WriteCalls() != 1) { return 12; }
        transport.SetFailWrite(true);
        if (disk.Write(2, 1, source) != BlockStatus.IoFailure() ||
            source[0] != 77) { return 13; }

        BlockDevice failed = new BlockDevice(new MockBlockTransport(true, false));
        byte[] unchanged = new byte[512]; unchanged[0] = 91; unchanged[511] = 92;
        if (failed.Read(0, 1, unchanged) != BlockStatus.IoFailure() ||
            unchanged[0] != 91 || unchanged[511] != 92) { return 7; }
        BlockDevice flushFailed = new BlockDevice(new MockBlockTransport(false, true));
        if (flushFailed.Flush() != BlockStatus.IoFailure()) { return 8; }
        BlockDevice invalid = new BlockDevice(new InvalidBlockTransport());
        if (invalid.Read(0, 1, new byte[768]) != BlockStatus.InvalidArgument() ||
            invalid.Flush() != BlockStatus.InvalidArgument()) { return 9; }
        BlockDevice missing = new BlockDevice(null);
        if (missing.Read(0, 1, sector) != BlockStatus.Unavailable() || missing.Flush() != BlockStatus.Unavailable()) { return 10; }
        if (missing.Write(0, 1, source) != BlockStatus.Unavailable() ||
            invalid.Write(0, 1, new byte[768]) != BlockStatus.InvalidArgument()) { return 14; }
        System.Console.WriteLine("Australis block-device tests passed");
        return 0;
    }
}
