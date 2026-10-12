using Australis.Kernel.Storage;
using Australis.Kernel.Vfs;

public class Hyfs2MemoryTransport : IBlockTransport {
    private byte[] image;
    private bool failReads;
    public Hyfs2MemoryTransport(byte[] input) { image = input; failReads = false; }
    public void FailReads(bool value) { failReads = value; }
    public int SectorSize() { return 512; }
    public long SectorCount() { return image.Length / 512; }
    public bool Flush() { return true; }
    public bool Write(long lba, int sectors, byte[] source) { return false; }
    public bool Read(long lba, int sectors, byte[] destination) {
        if (failReads || lba < 0 || sectors < 1 || lba >= SectorCount() ||
            sectors > SectorCount() - lba || destination == null ||
            destination.Length < sectors * 512) { return false; }
        int source = (int)(lba * 512);
        int index = 0;
        while (index < sectors * 512) {
            destination[index] = image[source + index]; index = index + 1;
        }
        return true;
    }
}

public class Hyfs2Program {
    public static int Main() {
        byte[] image = System.IO.File.ReadAllBytes("build/hyfs2-host.img");
        Partition root = new Partition(true, true, 0, 0, image.Length / 512);
        Hyfs2MemoryTransport transport = new Hyfs2MemoryTransport(image);
        BlockDevice disk = new BlockDevice(transport);
        Hyfs2 filesystem = new Hyfs2();
        if (filesystem.Mount(disk, root) != VfsStatus.Ok() ||
            filesystem.Generation() < 2) { return 1; }
        VfsFileInfo directory = filesystem.Stat("/System/Core");
        VfsFileInfo program = filesystem.Stat("/System/Core/System.exec");
        if (!directory.Exists() || directory.Kind() != 2 ||
            !directory.HasCreationTime() || directory.CreatedUnixSeconds() != 1735689600 ||
            !program.Exists() ||
            program.Kind() != 1 || program.ByteLength() != 4 ||
            !program.HasModificationTime() ||
            program.ModifiedUnixSeconds() != 1735689600) { return 2; }
        byte[] bytes = new byte[4];
        if (filesystem.ReadFile("/System/Core/System.exec", 0, bytes) != VfsStatus.Ok() ||
            bytes[0] != 65 || bytes[1] != 85 || bytes[2] != 69 || bytes[3] != 88) {
            return 3;
        }
        transport.FailReads(true);
        if (filesystem.ReadFile("/System/Core/System.exec", 0, bytes) !=
                VfsStatus.IoFailure() ||
            new Hyfs2().Mount(disk, root) != VfsStatus.IoFailure()) { return 31; }
        transport.FailReads(false);
        if (!filesystem.Exists("/Users/note+1.txt") ||
            filesystem.Stat("/missing").Status() != VfsStatus.NotFound() ||
            filesystem.Stat("/System/Core/System.exec/").Status() != VfsStatus.InvalidArgument() ||
            filesystem.DirectorySlotCount() != 2) { return 4; }
        byte[] name = new byte[64];
        if (filesystem.DirectorySlotCountAt("/System") != 1 ||
            filesystem.CopyDirectoryEntryNameAt("/System", 0, name) != 4 ||
            name[0] != 67 || name[3] != 101 ||
            filesystem.DirectorySlotCountAt("/System/Core") != 1 ||
            filesystem.DirectorySlotCountAt("/System/Core/System.exec") >= 0) { return 41; }
        Vfs vfs = new Vfs();
        if (vfs.MountRoot(filesystem, disk, root) != VfsStatus.Ok() ||
            vfs.OpenRootFile("/System").IsOpen() ||
            !vfs.OpenRootFile("/System/Core/System.exec").IsOpen() ||
            vfs.DirectorySlotCountAt("/System/Core") != 1) { return 5; }
        VfsDirectoryHandle nested = vfs.OpenRootDirectory("/System/Core");
        if (!nested.IsOpen() || nested.Count() != 1 ||
            nested.Next(name) != 11 || nested.Next(name) != -1 ||
            nested.Status() != VfsStatus.EndOfFile()) { return 51; }
        HyfsAuto automatic = new HyfsAuto();
        if (automatic.Mount(disk, root) != VfsStatus.Ok() ||
            automatic.Stat("/System/Core").Kind() != 2) { return 6; }
        byte[] oldImage = System.IO.File.ReadAllBytes("build/hyfs-v1-compat.img");
        BlockDevice oldDisk = new BlockDevice(new Hyfs2MemoryTransport(oldImage));
        Partition oldRoot = new Partition(true, true, 0, 0, oldImage.Length / 512);
        HyfsAuto oldAutomatic = new HyfsAuto();
        if (oldAutomatic.Mount(oldDisk, oldRoot) != VfsStatus.Ok() ||
            !oldAutomatic.Stat("/boot+txt").Exists() ||
            oldAutomatic.DirectorySlotCountAt("/") != 2) { return 7; }
        byte[] damaged = new byte[image.Length];
        int copy = 0;
        while (copy < image.Length) { damaged[copy] = image[copy]; copy = copy + 1; }
        damaged[512] = 0;
        BlockDevice damagedDisk = new BlockDevice(new Hyfs2MemoryTransport(damaged));
        Hyfs2 recovered = new Hyfs2();
        if (recovered.Mount(damagedDisk, root) != VfsStatus.Ok() ||
            recovered.Generation() != 5 ||
            !recovered.Stat("/System/Core/System.exec").Exists() ||
            recovered.Stat("/Users/note+1.txt").Exists()) { return 8; }
        damaged[0] = 0;
        if (new Hyfs2().Mount(damagedDisk, root) == VfsStatus.Ok()) { return 9; }
        System.Console.WriteLine("Australis HyFS v2 reader tests passed");
        return 0;
    }
}
