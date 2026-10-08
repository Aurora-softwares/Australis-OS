namespace Australis.Kernel.Storage {
    // Synchronous, all-or-nothing block I/O contract shared by AHCI, NVMe and
    // later USB mass-storage providers. A provider only receives requests that
    // have passed the range and buffer checks below.
    public interface IBlockTransport {
        int SectorSize();
        long SectorCount();
        bool Read(long lba, int sectors, byte[] destination);
        bool Flush();
    }

    public class BlockStatus {
        public static int Ok() { return 0; }
        public static int Unavailable() { return 1; }
        public static int InvalidArgument() { return 2; }
        public static int OutOfRange() { return 3; }
        public static int IoFailure() { return 4; }
    }

    public class BlockGeometry {
        private int sectorSize;
        private long sectorCount;

        public BlockGeometry(int inputSectorSize, long inputSectorCount) {
            sectorSize = inputSectorSize;
            sectorCount = inputSectorCount;
        }

        public int SectorSize() { return sectorSize; }
        public long SectorCount() { return sectorCount; }

        // Storage transports use power-of-two logical sectors. Restricting the
        // bootstrap contract to 512 through 4096 bytes prevents byte-count
        // overflow and keeps the page-backed DMA path naturally aligned.
        public bool IsValid() {
            if (sectorCount <= 0 || sectorSize < 512 || sectorSize > 4096) { return false; }
            return sectorSize == 512 || sectorSize == 1024 || sectorSize == 2048 || sectorSize == 4096;
        }
    }

    public class BlockDevice {
        private IBlockTransport transport;
        private BlockGeometry geometry;
        private int lastStatus;

        public BlockDevice(IBlockTransport inputTransport) {
            transport = inputTransport;
            geometry = new BlockGeometry(0, 0);
            lastStatus = BlockStatus.Unavailable();
            if (transport != null) {
                geometry = new BlockGeometry(transport.SectorSize(), transport.SectorCount());
                if (!geometry.IsValid()) { lastStatus = BlockStatus.InvalidArgument(); }
            }
        }

        public int SectorSize() { return geometry.SectorSize(); }
        public long SectorCount() { return geometry.SectorCount(); }
        public int LastStatus() { return lastStatus; }

        // A request either transfers every requested sector or reports failure.
        // The subtraction form is deliberate: `lba + sectors` could overflow a
        // signed 64-bit value before the capacity comparison.
        public int Read(long lba, int sectors, byte[] destination) {
            if (transport == null) { lastStatus = BlockStatus.Unavailable(); return lastStatus; }
            if (!geometry.IsValid() || lba < 0 || sectors < 1 || destination == null) {
                lastStatus = BlockStatus.InvalidArgument(); return lastStatus;
            }
            if (lba >= geometry.SectorCount() || sectors > geometry.SectorCount() - lba) {
                lastStatus = BlockStatus.OutOfRange(); return lastStatus;
            }
            if (sectors > destination.Length / geometry.SectorSize()) {
                lastStatus = BlockStatus.InvalidArgument(); return lastStatus;
            }
            if (!transport.Read(lba, sectors, destination)) {
                lastStatus = BlockStatus.IoFailure(); return lastStatus;
            }
            lastStatus = BlockStatus.Ok();
            return lastStatus;
        }

        public int Flush() {
            if (transport == null) { lastStatus = BlockStatus.Unavailable(); return lastStatus; }
            if (!transport.Flush()) { lastStatus = BlockStatus.IoFailure(); return lastStatus; }
            lastStatus = BlockStatus.Ok();
            return lastStatus;
        }
    }
}
