using Australis.Kernel.Storage;

namespace Australis.Kernel.Vfs {
    // Filesystem drivers mount a bounded partition instead of an entire disk.
    // Paths are deliberately left as UTF-8 strings at this layer; HyFS and
    // compatibility drivers own their on-disk name encoding and lookup rules.
    public interface IFileSystem {
        int Mount(BlockDevice device, Partition partition);
        bool Exists(string path);
        int ReadFile(string path, long offset, byte[] destination);
    }

    public class VfsStatus {
        public static int Ok() { return 0; }
        public static int InvalidArgument() { return 1; }
        public static int MountFailed() { return 2; }
        public static int NotMounted() { return 3; }
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
            lastStatus = VfsStatus.Ok();
            return rootFileSystem.Exists(path);
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
    }
}
