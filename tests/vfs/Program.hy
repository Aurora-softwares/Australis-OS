using Australis.Kernel.Storage;
using Australis.Kernel.Vfs;

public class MockTransport : IBlockTransport {
    public int SectorSize() { return 512; }
    public long SectorCount() { return 128; }
    public bool Read(long lba, int sectors, byte[] destination) { return true; }
    public bool Flush() { return true; }
}

public class MockFileSystem : IFileSystem {
    private bool failMount;
    private int mountCalls;
    private int readCalls;

    public MockFileSystem(bool inputFailMount) {
        failMount = inputFailMount;
        mountCalls = 0;
        readCalls = 0;
    }

    public int Mount(BlockDevice device, Partition partition) {
        mountCalls = mountCalls + 1;
        if (failMount) { return VfsStatus.MountFailed(); }
        return VfsStatus.Ok();
    }
    public bool Exists(string path) { return path == "/shell.hy"; }
    public VfsFileInfo Stat(string path) {
        if (path == "/shell.hy") { return new VfsFileInfo(VfsStatus.Ok(), 2); }
        return new VfsFileInfo(VfsStatus.NotFound(), 0);
    }
    public int ReadFile(string path, long offset, byte[] destination) {
        readCalls = readCalls + 1;
        if (path != "/shell.hy" || offset != 0 || destination.Length < 2) { return VfsStatus.InvalidArgument(); }
        destination[0] = 72; destination[1] = 121;
        return VfsStatus.Ok();
    }
    public int MountCalls() { return mountCalls; }
    public int ReadCalls() { return readCalls; }
}

public class Program {
    public static int Main() {
        Vfs vfs = new Vfs();
        byte[] bytes = new byte[2];
        if (vfs.ReadRootFile("/shell.hy", 0, bytes) != VfsStatus.NotMounted()) { return 1; }

        BlockDevice device = new BlockDevice(new MockTransport());
        Partition outside = new Partition(true, true, 0, 120, 16);
        MockFileSystem neverMounted = new MockFileSystem(false);
        if (vfs.MountRoot(neverMounted, device, outside) != VfsStatus.InvalidArgument() || neverMounted.MountCalls() != 0) { return 2; }

        Partition root = new Partition(true, true, 0, 64, 32);
        MockFileSystem failed = new MockFileSystem(true);
        if (vfs.MountRoot(failed, device, root) != VfsStatus.MountFailed() || failed.MountCalls() != 1 || vfs.IsRootMounted()) { return 3; }

        MockFileSystem mounted = new MockFileSystem(false);
        if (vfs.MountRoot(mounted, device, root) != VfsStatus.Ok() || !vfs.IsRootMounted()) { return 4; }
        if (!vfs.Exists("/shell.hy") || vfs.Exists("/missing")) { return 5; }
        if (vfs.StatRootFile("/shell.hy").ByteLength() != 2 || vfs.StatRootFile("/missing").Status() != VfsStatus.NotFound()) { return 51; }
        if (vfs.ReadRootFile("/shell.hy", 0, bytes) != VfsStatus.Ok() || bytes[0] != 72 || bytes[1] != 121 || mounted.ReadCalls() != 1) { return 6; }
        if (vfs.ReadRootFile("/shell.hy", -1, bytes) != VfsStatus.InvalidArgument()) { return 7; }
        MockFileSystem failedRemount = new MockFileSystem(true);
        if (vfs.MountRoot(failedRemount, device, root) != VfsStatus.MountFailed() || vfs.IsRootMounted() ||
            vfs.ReadRootFile("/shell.hy", 0, bytes) != VfsStatus.NotMounted()) { return 8; }
        System.Console.WriteLine("Australis VFS tests passed");
        return 0;
    }
}
