using Australis.Kernel.Storage;
using Australis.Kernel.Vfs;

public class WriterTransport : IBlockTransport {
    private byte[] image;
    private int writes;
    private int flushes;
    private int failWriteAt;
    private int failFlushAt;
    private bool removed;

    public WriterTransport(byte[] input) {
        image = input; writes = 0; flushes = 0;
        failWriteAt = 0; failFlushAt = 0; removed = false;
    }
    public int SectorSize() { return 512; }
    public long SectorCount() { return image.Length / 512; }
    public void FailWriteAfter(int count) { failWriteAt = writes + count; }
    public void FailFlushAfter(int count) { failFlushAt = flushes + count; }
    public void Remove() { removed = true; }
    public void Restore() { removed = false; }
    public int Writes() { return writes; }
    public int Flushes() { return flushes; }
    public byte[] Image() { return image; }
    public bool Read(long lba, int sectors, byte[] destination) {
        if (removed || lba < 0 || sectors < 1 || lba >= SectorCount() ||
            sectors > SectorCount() - lba || destination == null ||
            destination.Length < sectors * 512) { return false; }
        int start = (int)(lba * 512);
        int index = 0;
        while (index < sectors * 512) {
            destination[index] = image[start + index]; index = index + 1;
        }
        return true;
    }
    public bool Write(long lba, int sectors, byte[] source) {
        if (removed || lba < 0 || sectors < 1 || lba >= SectorCount() ||
            sectors > SectorCount() - lba || source == null ||
            source.Length < sectors * 512) { return false; }
        writes = writes + 1;
        int length = sectors * 512;
        if (writes == failWriteAt) { length = 16; }
        int start = (int)(lba * 512);
        int index = 0;
        while (index < length) {
            image[start + index] = source[index]; index = index + 1;
        }
        return writes != failWriteAt;
    }
    public bool Flush() {
        flushes = flushes + 1;
        return !removed && flushes != failFlushAt;
    }
}

public class Hyfs2WriterProgram {
    private static byte[] Two(int a, int b) {
        byte[] result = new byte[2];
        result[0] = (byte)a; result[1] = (byte)b;
        return result;
    }
    private static byte[] Three(int a, int b, int c) {
        byte[] result = new byte[3];
        result[0] = (byte)a; result[1] = (byte)b; result[2] = (byte)c;
        return result;
    }
    private static byte[] Four(int a, int b, int c, int d) {
        byte[] result = new byte[4];
        result[0] = (byte)a; result[1] = (byte)b;
        result[2] = (byte)c; result[3] = (byte)d;
        return result;
    }
    private static byte[] Clone(byte[] source) {
        byte[] copy = new byte[source.Length];
        int i = 0;
        while (i < source.Length) { copy[i] = source[i]; i = i + 1; }
        return copy;
    }

    private static bool BytesAre(Hyfs2 filesystem, string path, byte[] expected) {
        if (filesystem.Stat(path).ByteLength() != expected.Length) { return false; }
        byte[] actual = new byte[expected.Length];
        if (filesystem.ReadFile(path, 0, actual) != VfsStatus.Ok()) { return false; }
        int i = 0;
        while (i < actual.Length) {
            if (actual[i] != expected[i]) { return false; }
            i = i + 1;
        }
        return true;
    }

    private static int Interrupted(byte[] fixture, Partition volume, int stage,
        bool flush) {
        WriterTransport io = new WriterTransport(Clone(fixture));
        BlockDevice device = new BlockDevice(io);
        Hyfs2 writer = new Hyfs2();
        if (writer.MountWritable(device, volume) != VfsStatus.Ok()) { return 1; }
        long generation = writer.Generation();
        if (flush) { io.FailFlushAfter(stage); }
        else { io.FailWriteAfter(stage); }
        byte[] data = new byte[700];
        int i = 0;
        while (i < data.Length) { data[i] = (byte)(i % 239); i = i + 1; }
        if (writer.CreateFile("/crash.bin", data) != VfsStatus.IoFailure() ||
            writer.IsMounted()) { return 2; }
        Hyfs2 recovered = new Hyfs2();
        if (recovered.Mount(device, volume) != VfsStatus.Ok()) { return 3; }
        bool exists = recovered.Exists("/crash.bin");
        if (stage < 3 || !flush) {
            if (exists || recovered.Generation() != generation) { return 4; }
        } else {
            if (recovered.Generation() != generation &&
                recovered.Generation() != generation + 1) { return 5; }
            if (exists && !BytesAre(recovered, "/crash.bin", data)) { return 6; }
        }
        if (!BytesAre(recovered, "/System/Core/System.exec",
            Four(65, 85, 69, 88))) { return 7; }
        return 0;
    }

    public static int Main() {
        byte[] fixture = System.IO.File.ReadAllBytes("build/hyfs2-host.img");
        Partition volume = new Partition(true, true, 0, 0, fixture.Length / 512);
        WriterTransport io = new WriterTransport(Clone(fixture));
        BlockDevice device = new BlockDevice(io);
        Hyfs2 readOnly = new Hyfs2();
        if (readOnly.Mount(device, volume) != VfsStatus.Ok() ||
            readOnly.CreateFile("/new", new byte[0]) != VfsStatus.ReadOnly()) { return 1; }
        Hyfs2 writer = new Hyfs2();
        if (writer.MountWritable(device, volume) != VfsStatus.Ok() ||
            !writer.IsWritable()) { return 2; }
        if (writer.Mkdir("/Workspace") != VfsStatus.Ok() ||
            writer.CreateFile("/Workspace/item", Three(97, 98, 99)) !=
                VfsStatus.Ok() ||
            writer.CreateFile("/Workspace/item", new byte[0]) !=
                VfsStatus.AlreadyExists()) { return 3; }
        long firstId = writer.Stat("/Workspace/item").ObjectId();
        if (writer.ReplaceFile("/Workspace/item", Two(120, 121)) !=
            VfsStatus.Ok()) { return 4; }
        byte[] suffix = new byte[700];
        int i = 0;
        while (i < suffix.Length) { suffix[i] = (byte)(i % 239); i = i + 1; }
        if (writer.AppendFile("/Workspace/item", suffix) != VfsStatus.Ok()) { return 5; }
        byte[] appended = new byte[702];
        appended[0] = 120; appended[1] = 121;
        i = 0;
        while (i < suffix.Length) { appended[i + 2] = suffix[i]; i = i + 1; }
        if (!BytesAre(writer, "/Workspace/item", appended)) { return 6; }
        if (writer.TruncateFile("/Workspace/item", 900) != VfsStatus.Ok()) { return 7; }
        byte[] extended = new byte[900];
        i = 0;
        while (i < appended.Length) { extended[i] = appended[i]; i = i + 1; }
        if (!BytesAre(writer, "/Workspace/item", extended) ||
            writer.TruncateFile("/Workspace/item", 3) != VfsStatus.Ok() ||
            !BytesAre(writer, "/Workspace/item", Three(120, 121, 0))) {
            return 8;
        }
        if (writer.TruncateFile("/Workspace/item", 0) != VfsStatus.Ok() ||
            !BytesAre(writer, "/Workspace/item", new byte[0]) ||
            writer.AppendFile("/Workspace/item", Three(88, 89, 90)) !=
                VfsStatus.Ok() ||
            !BytesAre(writer, "/Workspace/item", Three(88, 89, 90)) ||
            writer.Mkdir("/Workspace/sub") != VfsStatus.Ok()) { return 17; }
        if (writer.Rmdir("/Workspace") != VfsStatus.NotEmpty() ||
            writer.Rename("/Workspace", "/Workspace/sub/loop") !=
                VfsStatus.InvalidArgument() ||
            writer.Rename("/Workspace/item", "/Users/moved") != VfsStatus.Ok() ||
            writer.Stat("/Users/moved").ObjectId() != firstId ||
            writer.Rmdir("/Workspace/sub") != VfsStatus.Ok() ||
            writer.Rmdir("/Workspace") != VfsStatus.Ok()) { return 9; }
        if (writer.DeleteFile("/Users/moved") != VfsStatus.Ok() ||
            writer.Mkdir("/Workspace/") != VfsStatus.Ok() ||
            writer.Rmdir("/Workspace/") != VfsStatus.Ok() ||
            writer.CreateFile("/new", new byte[0]) != VfsStatus.Ok() ||
            writer.Stat("/new").ObjectId() <= firstId) { return 10; }
        if (writer.DeleteFile("/new") != VfsStatus.Ok() ||
            writer.CreateFile("/newer", new byte[0]) != VfsStatus.Ok() ||
            writer.Stat("/newer").ObjectId() <= firstId) { return 11; }
        if (writer.Mkdir("/Tree") != VfsStatus.Ok() ||
            writer.CreateFile("/Tree/leaf", Three(1, 2, 3)) != VfsStatus.Ok()) {
            return 18;
        }
        long treeId = writer.Stat("/Tree").ObjectId();
        if (writer.Rename("/Tree", "/Users/Tree") != VfsStatus.Ok() ||
            writer.Stat("/Users/Tree").ObjectId() != treeId ||
            !BytesAre(writer, "/Users/Tree/leaf", Three(1, 2, 3)) ||
            writer.Exists("/Tree") ||
            writer.DeleteFile("/Users/Tree/leaf") != VfsStatus.Ok() ||
            writer.Rmdir("/Users/Tree") != VfsStatus.Ok()) { return 19; }
        if (writer.CreateFile("/missing/new", new byte[0]) != VfsStatus.NotFound() ||
            writer.CreateFile("/bad/", new byte[0]) != VfsStatus.InvalidArgument()) {
            return 12;
        }
        int writesBeforeFull = io.Writes();
        byte[] tooLarge = new byte[fixture.Length];
        if (writer.CreateFile("/too-large", tooLarge) != VfsStatus.NoSpace() ||
            io.Writes() != writesBeforeFull || writer.Exists("/too-large")) { return 14; }
        Hyfs2 remounted = new Hyfs2();
        if (remounted.Mount(device, volume) != VfsStatus.Ok() ||
            remounted.Exists("/Workspace") || remounted.Exists("/Users/moved") ||
            !remounted.Exists("/newer") ||
            !BytesAre(remounted, "/System/Core/System.exec",
                Four(65, 85, 69, 88))) { return 13; }
        WriterTransport rollbackIo = new WriterTransport(Clone(fixture));
        BlockDevice rollbackDisk = new BlockDevice(rollbackIo);
        Hyfs2 rollbackWriter = new Hyfs2();
        if (rollbackWriter.MountWritable(rollbackDisk, volume) != VfsStatus.Ok() ||
            rollbackWriter.CreateFile("/rollback", Three(65, 66, 67)) != VfsStatus.Ok() ||
            rollbackWriter.ReplaceFile("/rollback", Three(88, 89, 90)) != VfsStatus.Ok()) {
            return 15;
        }
        // The newest slot is block 1 after two commits. Its loss must expose
        // the preceding complete generation and its original file extent.
        rollbackIo.Image()[512] = 0;
        Hyfs2 rollback = new Hyfs2();
        if (rollback.Mount(rollbackDisk, volume) != VfsStatus.Ok() ||
            !BytesAre(rollback, "/rollback", Three(65, 66, 67))) { return 16; }
        byte[] oneSlot = Clone(fixture);
        oneSlot[0] = 0;
        WriterTransport mirrorIo = new WriterTransport(oneSlot);
        BlockDevice mirrorDisk = new BlockDevice(mirrorIo);
        Hyfs2 mirrorWriter = new Hyfs2();
        if (mirrorWriter.MountWritable(mirrorDisk, volume) != VfsStatus.Ok() ||
            mirrorIo.Writes() != 1 || mirrorIo.Flushes() != 1 ||
            mirrorWriter.CreateFile("/repair", Three(4, 5, 6)) != VfsStatus.Ok()) {
            return 25;
        }
        Hyfs2 mirrorReader = new Hyfs2();
        if (mirrorReader.Mount(mirrorDisk, volume) != VfsStatus.Ok() ||
            !BytesAre(mirrorReader, "/repair", Three(4, 5, 6))) { return 26; }
        WriterTransport vfsIo = new WriterTransport(Clone(fixture));
        BlockDevice vfsDisk = new BlockDevice(vfsIo);
        Vfs data = new Vfs();
        Hyfs2 dataFs = new Hyfs2();
        if (data.MountRootWritableAs(dataFs, vfsDisk, volume, 3) !=
            VfsStatus.Ok()) { return 40; }
        VfsDirectoryHandle oldDirectory = data.OpenRootDirectory("/");
        if (!oldDirectory.IsOpen() || oldDirectory.Count() < 1) { return 61; }
        if (data.CreateRootFile("/sample", Three(1, 2, 3)) != VfsStatus.Ok() ||
            data.CreateRootFile("/sample", new byte[0]) != VfsStatus.AlreadyExists() ||
            data.MkdirRoot("/dir") != VfsStatus.Ok() ||
            data.DirectoryInfoAt("/").Status() != VfsStatus.Ok() ||
            data.DirectoryInfoAt("/dir").Count() != 0 ||
            data.DirectoryInfoAt("/sample").Status() != VfsStatus.InvalidArgument()) {
            return 41;
        }
        if (oldDirectory.Next(new byte[64]) != -1 ||
            oldDirectory.Status() != VfsStatus.StaleHandle()) { return 62; }
        VfsFileHandle writableHandle = data.OpenRootFileWrite("/sample");
        VfsFileHandle readHandle = data.OpenRootFile("/sample");
        if (!writableHandle.IsOpen() || !readHandle.IsOpen() ||
            writableHandle.Append(Two(4, 5)) != VfsStatus.Ok() ||
            writableHandle.Truncate(4) != VfsStatus.Ok() ||
            !BytesAre(dataFs, "/sample", Four(1, 2, 3, 4)) ||
            writableHandle.Replace(Two(9, 8)) != VfsStatus.Ok() ||
            !BytesAre(dataFs, "/sample", Two(9, 8))) { return 42; }
        byte[] vfsRead = new byte[2];
        if (readHandle.Read(vfsRead) != VfsStatus.StaleHandle()) { return 43; }
        VfsFileHandle currentRead = data.OpenRootFile("/sample");
        if (currentRead.Read(vfsRead) != VfsStatus.Ok() ||
            vfsRead[0] != 9 || vfsRead[1] != 8) { return 44; }
        if (data.RenameRoot("/sample", "/dir/sample") != VfsStatus.Ok() ||
            writableHandle.Append(Two(1, 1)) != VfsStatus.StaleHandle() ||
            data.RmdirRoot("/dir") != VfsStatus.NotEmpty() ||
            data.DeleteRootFile("/dir/sample") != VfsStatus.Ok() ||
            data.RmdirRoot("/dir") != VfsStatus.Ok()) { return 45; }
        Vfs readOnlyVfs = new Vfs();
        if (readOnlyVfs.MountRoot(new Hyfs2(), vfsDisk, volume) != VfsStatus.Ok() ||
            readOnlyVfs.CreateRootFile("/blocked", new byte[0]) != VfsStatus.ReadOnly() ||
            readOnlyVfs.OpenRootFileWrite("/System/Core/System.exec").Status() !=
                VfsStatus.ReadOnly()) { return 46; }
        int vfsWrites = vfsIo.Writes();
        vfsIo.FailWriteAfter(1);
        if (data.CreateRootFile("/fails", Three(7, 8, 9)) != VfsStatus.IoFailure() ||
            data.IsRootMounted() || vfsIo.Writes() != vfsWrites + 1 ||
            currentRead.Read(new byte[0]) != VfsStatus.NotMounted()) { return 48; }

        // A disappearing device must invalidate the writer and every open
        // handle. The last committed snapshot must survive reinsertion.
        WriterTransport removalIo = new WriterTransport(Clone(fixture));
        BlockDevice removalDisk = new BlockDevice(removalIo);
        Vfs removedVolume = new Vfs();
        if (removedVolume.MountRootWritableAs(new Hyfs2(), removalDisk,
            volume, 3) != VfsStatus.Ok() ||
            removedVolume.CreateRootFile("/retained", Three(1, 2, 3)) !=
                VfsStatus.Ok()) { return 49; }
        VfsFileHandle removedHandle = removedVolume.OpenRootFileWrite("/retained");
        VfsDirectoryHandle removedDirectory = removedVolume.OpenRootDirectory("/");
        int writesBeforeRemoval = removalIo.Writes();
        removalIo.Remove();
        if (removedHandle.Append(Two(4, 5)) != VfsStatus.IoFailure() ||
            removedVolume.IsRootMounted() ||
            removedHandle.Append(Two(6, 7)) != VfsStatus.NotMounted() ||
            removalIo.Writes() != writesBeforeRemoval ||
            removedDirectory.Next(new byte[64]) != -1 ||
            removedDirectory.Status() != VfsStatus.NotMounted() ||
            removedVolume.MountRootWritableAs(new Hyfs2(), removalDisk,
                volume, 3) == VfsStatus.Ok()) { return 50; }
        removalIo.Restore();
        Hyfs2 afterRemoval = new Hyfs2();
        if (afterRemoval.Mount(removalDisk, volume) != VfsStatus.Ok() ||
            !BytesAre(afterRemoval, "/retained", Three(1, 2, 3))) { return 51; }
        Vfs readRemoval = new Vfs();
        if (readRemoval.MountRootWritableAs(new Hyfs2(), removalDisk,
            volume, 3) != VfsStatus.Ok()) { return 59; }
        VfsFileHandle lostRead = readRemoval.OpenRootFile("/retained");
        removalIo.Remove();
        if (lostRead.Read(new byte[1]) != VfsStatus.IoFailure() ||
            readRemoval.IsRootMounted() ||
            lostRead.Read(new byte[1]) != VfsStatus.NotMounted()) { return 60; }
        removalIo.Restore();

        // Repeated deletion and reuse must not exhaust the free space, and a
        // larger directory must remain intact through cross-directory moves.
        WriterTransport churnIo = new WriterTransport(Clone(fixture));
        BlockDevice churnDisk = new BlockDevice(churnIo);
        Hyfs2 churn = new Hyfs2();
        if (churn.MountWritable(churnDisk, volume) != VfsStatus.Ok() ||
            churn.Mkdir("/Many") != VfsStatus.Ok()) { return 52; }
        int cycle = 0;
        while (cycle < 40) {
            if (churn.CreateFile("/Many/temporary", Three(1, 2, 3)) !=
                    VfsStatus.Ok() ||
                churn.DeleteFile("/Many/temporary") != VfsStatus.Ok()) {
                return 53;
            }
            cycle = cycle + 1;
        }
        if (churn.Mkdir("/Many/Sub") != VfsStatus.Ok()) { return 54; }
        cycle = 0;
        while (cycle < 24) {
            string path = "/Many/item" + cycle;
            if (churn.CreateFile(path, Two(cycle, cycle + 1)) !=
                VfsStatus.Ok()) { return 55; }
            cycle = cycle + 1;
        }
        if (churn.Rename("/Many/item0", "/Many/Sub/moved") != VfsStatus.Ok() ||
            !BytesAre(churn, "/Many/Sub/moved", Two(0, 1))) { return 56; }
        Hyfs2 afterChurn = new Hyfs2();
        if (afterChurn.Mount(churnDisk, volume) != VfsStatus.Ok() ||
            afterChurn.DirectorySlotCountAt("/Many") != 24 ||
            !BytesAre(afterChurn, "/Many/Sub/moved", Two(0, 1)) ||
            !BytesAre(afterChurn, "/Many/item23", Two(23, 24))) { return 57; }

        byte[] noSlots = Clone(fixture);
        noSlots[0] = 0; noSlots[512] = 0;
        if (new Hyfs2().Mount(new BlockDevice(new WriterTransport(noSlots)),
            volume) != VfsStatus.MountFailed()) { return 58; }
        int stage = 1;
        while (stage <= 4) {
            if (Interrupted(fixture, volume, stage, false) != 0) { return 20 + stage; }
            if (stage <= 3 && Interrupted(fixture, volume, stage, true) != 0) {
                return 30 + stage;
            }
            stage = stage + 1;
        }
        System.Console.WriteLine("Australis HyFS v2 writer tests passed");
        return 0;
    }
}
