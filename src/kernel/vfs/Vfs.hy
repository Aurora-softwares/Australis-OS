using Australis.Kernel.Storage;

namespace Australis.Kernel.Vfs {
    // Filesystem drivers mount a bounded partition instead of an entire disk.
    // Paths are deliberately left as UTF-8 strings at this layer; HyFS and
    // compatibility drivers own their on-disk name encoding and lookup rules.
    public interface IFileSystem {
        int Mount(BlockDevice device, Partition partition);
        bool Exists(string path);
        VfsFileInfo Stat(string path);
        int ReadFile(string path, long offset, byte[] destination);
        int DirectorySlotCount();
        int CopyDirectoryEntryName(int index, byte[] destination);
    }

    public class VfsStatus {
        public static int Ok() { return 0; }
        public static int InvalidArgument() { return 1; }
        public static int MountFailed() { return 2; }
        public static int NotMounted() { return 3; }
        public static int NotFound() { return 4; }
        public static int EndOfFile() { return 5; }
        public static int IoFailure() { return 6; }
        public static int Corrupt() { return 7; }
    }

    // File metadata returned by a filesystem lookup. A status-bearing value
    // avoids treating a zero-length file as indistinguishable from a missing
    // file, while keeping the VFS free of filesystem-specific metadata.
    public class VfsFileInfo {
        private int status;
        private long byteLength;

        public VfsFileInfo(int inputStatus, long inputByteLength) {
            status = inputStatus;
            byteLength = inputByteLength;
        }
        public int Status() { return status; }
        public long ByteLength() { return byteLength; }
        public bool Exists() { return status == VfsStatus.Ok(); }
    }

    // The initial VFS has one root mount. It performs the common block-range
    // validation once, so individual filesystem drivers can assume that every
    // `Partition` they receive is inside the owning live block device.
    public class Vfs {
        private IFileSystem rootFileSystem;
        private BlockDevice rootDevice;
        private Partition rootPartition;
        private int lastStatus;

        public Vfs() {
            rootFileSystem = null;
            rootDevice = null;
            rootPartition = new Partition(false, false, 0, 0, 0);
            lastStatus = VfsStatus.NotMounted();
        }

        public bool IsRootMounted() { return rootFileSystem != null; }
        public int LastStatus() { return lastStatus; }
        public Partition RootPartition() { return rootPartition; }

        public int MountRoot(IFileSystem fileSystem, BlockDevice device, Partition partition) {
            if (fileSystem == null || device == null || partition == null || !partition.Present() ||
                partition.FirstLba() < 0 || partition.BlockCount() <= 0 ||
                partition.FirstLba() >= device.SectorCount() ||
                partition.BlockCount() > device.SectorCount() - partition.FirstLba()) {
                lastStatus = VfsStatus.InvalidArgument();
                return lastStatus;
            }

            // A failed remount must not leave a stale root pointing at a
            // filesystem driver that may already have released its mount data.
            rootFileSystem = null;
            rootDevice = null;
            rootPartition = new Partition(false, false, 0, 0, 0);
            if (fileSystem.Mount(device, partition) != VfsStatus.Ok()) {
                lastStatus = VfsStatus.MountFailed();
                return lastStatus;
            }

            rootFileSystem = fileSystem;
            rootDevice = device;
            rootPartition = partition;
            lastStatus = VfsStatus.Ok();
            return lastStatus;
        }

        public bool Exists(string path) {
            if (rootFileSystem == null) {
                lastStatus = VfsStatus.NotMounted();
                return false;
            }
            if (path == null) { lastStatus = VfsStatus.InvalidArgument(); return false; }
            VfsFileInfo result = rootFileSystem.Stat(path);
            if (result == null) { lastStatus = VfsStatus.Corrupt(); return false; }
            lastStatus = result.Status();
            return result.Exists();
        }

        public VfsFileInfo StatRootFile(string path) {
            if (rootFileSystem == null) {
                lastStatus = VfsStatus.NotMounted();
                return new VfsFileInfo(lastStatus, 0);
            }
            if (path == null) {
                lastStatus = VfsStatus.InvalidArgument();
                return new VfsFileInfo(lastStatus, 0);
            }
            VfsFileInfo result = rootFileSystem.Stat(path);
            if (result == null) {
                lastStatus = VfsStatus.Corrupt();
                return new VfsFileInfo(lastStatus, 0);
            }
            lastStatus = result.Status();
            return result;
        }

        public int ReadRootFile(string path, long offset, byte[] destination) {
            if (rootFileSystem == null) {
                lastStatus = VfsStatus.NotMounted();
                return lastStatus;
            }
            if (path == null || offset < 0 || destination == null) {
                lastStatus = VfsStatus.InvalidArgument();
                return lastStatus;
            }
            lastStatus = rootFileSystem.ReadFile(path, offset, destination);
            return lastStatus;
        }

        // HyFS v1 has a flat root directory. Empty slots return a zero name
        // length; a negative result means the request failed.
        public int RootDirectorySlotCount() {
            if (rootFileSystem == null) { lastStatus = VfsStatus.NotMounted(); return -1; }
            lastStatus = VfsStatus.Ok();
            return rootFileSystem.DirectorySlotCount();
        }

        public int CopyRootDirectoryEntryName(int index, byte[] destination) {
            if (rootFileSystem == null) { lastStatus = VfsStatus.NotMounted(); return -1; }
            if (index < 0 || destination == null) { lastStatus = VfsStatus.InvalidArgument(); return -1; }
            int length = rootFileSystem.CopyDirectoryEntryName(index, destination);
            if (length < 0) { lastStatus = VfsStatus.InvalidArgument(); return -1; }
            lastStatus = VfsStatus.Ok();
            return length;
        }
    }
}
