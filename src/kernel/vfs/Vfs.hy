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

    public class VfsFileHandle {
        private Vfs owner;
        private string path;
        private int mountIdentity;
        private int mountGeneration;
        private long position;
        private long byteLength;
        private int status;
        private bool closed;
        public VfsFileHandle(Vfs inputOwner, string inputPath, int inputIdentity,
            int inputGeneration, long inputLength, int inputStatus) {
            owner = inputOwner; path = inputPath; mountIdentity = inputIdentity;
            mountGeneration = inputGeneration; position = 0; byteLength = inputLength;
            status = inputStatus; closed = inputStatus != VfsStatus.Ok();
        }
        public int Status() { return status; }
        public long Position() { return position; }
        public long ByteLength() { return byteLength; }
        public long Remaining() {
            if (closed || position >= byteLength) { return 0; }
            return byteLength - position;
        }
        public int MountIdentity() { return mountIdentity; }
        public bool IsOpen() { return !closed && status == VfsStatus.Ok(); }
        public int Read(byte[] destination) {
            if (closed || owner == null) { status = VfsStatus.NotMounted(); return status; }
            if (destination == null || destination.Length > byteLength - position) {
                status = VfsStatus.InvalidArgument(); return status;
            }
            status = owner.ReadOpenFile(path, mountIdentity, mountGeneration, position, destination);
            if (status == VfsStatus.Ok()) { position = position + destination.Length; }
            return status;
        }
        public void Close() { closed = true; owner = null; }
    }

    // A resolved namespace path keeps the mount selection separate from the
    // path passed to the filesystem. HyFS v1 remains a flat filesystem, but
    // the namespace can still canonicalize nested paths and cross the /usb
    // mount without teaching individual drivers about mount points.
    public class VfsPath {
        private int status;
        private Vfs volume;
        private string localPath;
        private string canonicalPath;
        public VfsPath(int inputStatus, Vfs inputVolume, string inputLocal,
            string inputCanonical) {
            status = inputStatus; volume = inputVolume;
            localPath = inputLocal; canonicalPath = inputCanonical;
        }
        public int Status() { return status; }
        public bool IsValid() { return status == VfsStatus.Ok() && volume != null; }
        public Vfs Volume() { return volume; }
        public string LocalPath() { return localPath; }
        public string CanonicalPath() { return canonicalPath; }
    }

    // The first mount namespace is deliberately small and deterministic:
    // / names the boot volume and /usb names the removable volume. Path
    // normalization is shared by the shell and user syscalls, so both observe
    // the same handling of repeated separators, dot, and parent traversal.
    public class VfsNamespace {
        private Vfs root;
        private Vfs removable;

        public VfsNamespace(Vfs inputRoot, Vfs inputRemovable) {
            root = inputRoot; removable = inputRemovable;
        }

        private int PathByte(string path, int index) {
            return System.Kernel.String.ByteAt(path, index);
        }

        public VfsPath Resolve(string path) {
            if (path == null || path.Length < 1 || path.Length > 255 || PathByte(path, 0) != 47) {
                return new VfsPath(VfsStatus.InvalidArgument(), null, null, null);
            }
            byte[] normalized = new byte[256];
            int[] restore = new int[64];
            normalized[0] = 47;
            int outputLength = 1;
            int depth = 0;
            int cursor = 1;
            while (cursor < path.Length) {
                while (cursor < path.Length && PathByte(path, cursor) == 47) { cursor = cursor + 1; }
                if (cursor >= path.Length) { break; }
                int start = cursor;
                while (cursor < path.Length && PathByte(path, cursor) != 47) { cursor = cursor + 1; }
                int componentLength = cursor - start;
                bool dot = componentLength == 1 && PathByte(path, start) == 46;
                bool parent = componentLength == 2 && PathByte(path, start) == 46 &&
                    PathByte(path, start + 1) == 46;
                if (dot) { continue; }
                if (parent) {
                    if (depth > 0) {
                        depth = depth - 1;
                        outputLength = restore[depth];
                    }
                    continue;
                }
                if (componentLength < 1 || componentLength > 63 || depth >= restore.Length) {
                    return new VfsPath(VfsStatus.InvalidArgument(), null, null, null);
                }
                int oldLength = outputLength;
                int required = componentLength;
                if (outputLength > 1) { required = required + 1; }
                if (required > normalized.Length - outputLength) {
                    return new VfsPath(VfsStatus.InvalidArgument(), null, null, null);
                }
                restore[depth] = oldLength;
                depth = depth + 1;
                if (outputLength > 1) {
                    normalized[outputLength] = 47;
                    outputLength = outputLength + 1;
                }
                int i = 0;
                while (i < componentLength) {
                    int value = PathByte(path, start + i);
                    if (value < 32 || value > 126) {
                        return new VfsPath(VfsStatus.InvalidArgument(), null, null, null);
                    }
                    normalized[outputLength] = (byte)value;
                    outputLength = outputLength + 1;
                    i = i + 1;
                }
            }

            string canonical = System.Kernel.String.FromBytes(normalized, outputLength);
            bool usb = outputLength >= 4 && normalized[0] == 47 && normalized[1] == 117 &&
                normalized[2] == 115 && normalized[3] == 98 &&
                (outputLength == 4 || normalized[4] == 47);
            if (!usb) {
                if (root == null || !root.IsRootMounted()) {
                    return new VfsPath(VfsStatus.NotMounted(), null, null, canonical);
                }
                return new VfsPath(VfsStatus.Ok(), root, canonical, canonical);
            }
            if (removable == null || !removable.IsRootMounted()) {
                return new VfsPath(VfsStatus.NotMounted(), null, null, canonical);
            }
            if (outputLength == 4) {
                return new VfsPath(VfsStatus.Ok(), removable, "/", canonical);
            }
            int localLength = outputLength - 4;
            byte[] localBytes = new byte[localLength];
            int localIndex = 0;
            while (localIndex < localLength) {
                localBytes[localIndex] = normalized[localIndex + 4];
                localIndex = localIndex + 1;
            }
            string local = System.Kernel.String.FromBytes(localBytes, localLength);
            return new VfsPath(VfsStatus.Ok(), removable, local, canonical);
        }

        public VfsFileInfo Stat(string path) {
            VfsPath resolved = Resolve(path);
            if (!resolved.IsValid()) { return new VfsFileInfo(resolved.Status(), 0); }
            return resolved.Volume().StatRootFile(resolved.LocalPath());
        }

        public VfsFileHandle Open(string path) {
            VfsPath resolved = Resolve(path);
            if (!resolved.IsValid()) {
                return new VfsFileHandle(null, path, 0, 0, 0, resolved.Status());
            }
            return resolved.Volume().OpenRootFile(resolved.LocalPath());
        }
    }

    // The initial VFS has one root mount. It performs the common block-range
    // validation once, so individual filesystem drivers can assume that every
    // `Partition` they receive is inside the owning live block device.
    public class Vfs {
        private IFileSystem rootFileSystem;
        private BlockDevice rootDevice;
        private Partition rootPartition;
        private int lastStatus;
        private int mountIdentity;
        private int mountGeneration;

        public Vfs() {
            rootFileSystem = null;
            rootDevice = null;
            rootPartition = new Partition(false, false, 0, 0, 0);
            lastStatus = VfsStatus.NotMounted();
            mountIdentity = 0; mountGeneration = 0;
        }

        public bool IsRootMounted() { return rootFileSystem != null; }
        public int LastStatus() { return lastStatus; }
        public Partition RootPartition() { return rootPartition; }
        public int MountIdentity() { return mountIdentity; }
        public int MountGeneration() { return mountGeneration; }

        public int MountRoot(IFileSystem fileSystem, BlockDevice device, Partition partition) {
            return MountRootAs(fileSystem, device, partition, 1);
        }

        public int MountRootAs(IFileSystem fileSystem, BlockDevice device, Partition partition,
            int identity) {
            if (fileSystem == null || device == null || partition == null || !partition.Present() ||
                identity < 1 ||
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
            mountIdentity = 0; mountGeneration = mountGeneration + 1;
            if (fileSystem.Mount(device, partition) != VfsStatus.Ok()) {
                lastStatus = VfsStatus.MountFailed();
                return lastStatus;
            }

            rootFileSystem = fileSystem;
            rootDevice = device;
            rootPartition = partition;
            mountIdentity = identity;
            lastStatus = VfsStatus.Ok();
            return lastStatus;
        }

        public void UnmountRoot() {
            rootFileSystem = null; rootDevice = null;
            rootPartition = new Partition(false, false, 0, 0, 0);
            mountIdentity = 0; mountGeneration = mountGeneration + 1;
            lastStatus = VfsStatus.NotMounted();
        }

        public VfsFileHandle OpenRootFile(string path) {
            VfsFileInfo info = StatRootFile(path);
            if (!info.Exists()) {
                return new VfsFileHandle(null, path, 0, 0, 0, info.Status());
            }
            return new VfsFileHandle(this, path, mountIdentity, mountGeneration,
                info.ByteLength(), VfsStatus.Ok());
        }

        public int ReadOpenFile(string path, int identity, int generation, long offset,
            byte[] destination) {
            if (rootFileSystem == null || identity != mountIdentity || generation != mountGeneration) {
                lastStatus = VfsStatus.NotMounted(); return lastStatus;
            }
            return ReadRootFile(path, offset, destination);
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
