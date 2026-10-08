namespace Australis.Kernel.Storage {
    // Five DMA pages are supplied by the platform: admin SQ/CQ, I/O SQ/CQ,
    // and one data page. The register aperture must be mapped uncached and
    // the pages must be accessible to the controller without an IOMMU mapping.
    public interface INvmeControllerIo {
        long Read32(int offset);
        void Write32(int offset, long value);
        long PhysicalPage(int index);
        void WriteDma(int page, int offset, byte[] source, int count);
        void ReadDma(int page, int offset, byte[] destination, int count);
        void Pause();
    }

    public class Nvme {
        private static void Write32(byte[] bytes, int offset, long value) {
            int i = 0;
            while (i < 4) { bytes[offset + i] = (byte)(value % 256); value = value / 256; i = i + 1; }
        }

        private static void Write64(byte[] bytes, int offset, long value) {
            int i = 0;
            while (i < 8) { bytes[offset + i] = (byte)(value % 256); value = value / 256; i = i + 1; }
        }

        private static long Read64(byte[] bytes, int offset) {
            long result = 0;
            long multiplier = 1;
            int i = 0;
            while (i < 8) {
                long value = bytes[offset + i];
                result = result + value * multiplier;
                if (i < 7) { multiplier = multiplier * 256; }
                i = i + 1;
            }
            return result;
        }

        // NVMe CSTS.RDY is the only completion condition used while enabling
        // or disabling a controller. Drivers must wait with a timeout derived
        // from CAP.TO before issuing commands.
        public static bool IsReady(long controllerStatus) { return controllerStatus % 2 != 0; }

        // CAP.DSTRD encodes 2^(2 + DSTRD) bytes between doorbells. Constrain the
        // bootstrap to values that fit the mapped 64 KiB controller aperture.
        public static int DoorbellStride(long capabilities) {
            long divisor = 65536; divisor = divisor * divisor;
            long high = capabilities / divisor;
            if (capabilities < 0 && capabilities % divisor != 0) { high = high - 1; }
            int exponent = (int)(high % 16);
            if (exponent < 0) { exponent = exponent + 16; }
            return DoorbellStrideFromHigh(exponent);
        }

        public static int DoorbellStrideFromHigh(long capabilitiesHigh) {
            if (capabilitiesHigh < 0) { return 0; }
            int exponent = (int)(capabilitiesHigh % 16);
            if (exponent > 7) { return 0; }
            int stride = 4;
            int i = 0;
            while (i < exponent) { stride = stride * 2; i = i + 1; }
            return stride;
        }

        // CC for 4 KiB memory pages, command-set 0 (NVM), and the standard
        // 64-byte SQE/16-byte CQE sizes. EN remains clear until ASQ/ACQ/AQA are
        // installed, then the transport sets bit 0 and polls CSTS.RDY.
        public static long ControllerConfiguration() { return 4587520; }

        // One 64-byte admin SQE for Identify Controller (CNS=1) or Identify
        // Namespace (CNS=0). PRP1 is a physical, page-aligned DMA buffer.
        public static bool BuildIdentify(byte[] command, int commandId, int namespaceId,
            bool controller, long dataPhysical) {
            if (command.Length < 64 || commandId < 0 || commandId > 65535 || namespaceId < 0 ||
                (!controller && namespaceId < 1) || dataPhysical < 0 || dataPhysical % 4096 != 0) { return false; }
            int i = 0; while (i < 64) { command[i] = 0; i = i + 1; }
            command[0] = 6;
            command[2] = (byte)(commandId % 256); command[3] = (byte)(commandId / 256);
            Write32(command, 4, namespaceId);
            Write64(command, 24, dataPhysical);
            if (controller) { command[40] = 1; }
            return true;
        }

        // One NVM Read command. A single PRP describes at most one 4 KiB page;
        // callers split larger requests until PRP-list support is installed.
        public static bool BuildRead(byte[] command, int commandId, int namespaceId, long dataPhysical,
            long lba, int blocks, int sectorSize) {
            if (command.Length < 64 || commandId < 0 || commandId > 65535 || namespaceId < 1 ||
                dataPhysical < 0 || dataPhysical % 4096 != 0 || lba < 0 || blocks < 1 ||
                (sectorSize != 512 && sectorSize != 1024 && sectorSize != 2048 && sectorSize != 4096) ||
                blocks > 4096 / sectorSize) { return false; }
            int i = 0; while (i < 64) { command[i] = 0; i = i + 1; }
            command[0] = 2;
            command[2] = (byte)(commandId % 256); command[3] = (byte)(commandId / 256);
            Write32(command, 4, namespaceId);
            Write64(command, 24, dataPhysical);
            Write64(command, 40, lba);
            command[48] = (byte)((blocks - 1) % 256);
            command[49] = (byte)((blocks - 1) / 256);
            return true;
        }

        // Parse the active namespace format. `NSZE` must be positive and only
        // 512..4096-byte logical blocks enter the common bootstrap block layer.
        public static int NamespaceSectorSize(byte[] identifyNamespace) {
            if (identifyNamespace.Length < 132) { return 0; }
            int activeFormat = identifyNamespace[26] % 16;
            int formatOffset = 128 + activeFormat * 4;
            if (formatOffset + 2 >= identifyNamespace.Length) { return 0; }
            int exponent = identifyNamespace[formatOffset + 2];
            int sectorSize = 1;
            int i = 0;
            while (i < exponent && sectorSize <= 4096) { sectorSize = sectorSize * 2; i = i + 1; }
            if (sectorSize != 512 && sectorSize != 1024 && sectorSize != 2048 && sectorSize != 4096) { return 0; }
            return sectorSize;
        }

        public static long NamespaceSectorCount(byte[] identifyNamespace) {
            if (identifyNamespace.Length < 8 || NamespaceSectorSize(identifyNamespace) == 0) { return 0; }
            long count = Read64(identifyNamespace, 0);
            if (count <= 0) { return 0; }
            return count;
        }
    }

    // Synchronous, polling NVMe 1.x bootstrap for namespace 1. Queue depth is
    // two and every transfer uses one page-aligned PRP, so no PRP list is
    // needed. Interrupts and writes are intentionally outside this reader.
    public class NvmeController : IBlockTransport {
        private static long U32Base() { long high = 65536; return high * high; }
        private INvmeControllerIo io;
        private int maximumPolls;
        private int stride;
        private int adminTail;
        private int adminHead;
        private int adminPhase;
        private int ioTail;
        private int ioHead;
        private int ioPhase;
        private int nextCommandId;
        private int sectorSize;
        private long sectorCount;
        private bool ready;

        public NvmeController(INvmeControllerIo inputIo, int inputMaximumPolls) {
            io = inputIo;
            maximumPolls = inputMaximumPolls;
            stride = 0;
            adminTail = 0; adminHead = 0; adminPhase = 1;
            ioTail = 0; ioHead = 0; ioPhase = 1;
            nextCommandId = 1;
            sectorSize = 0; sectorCount = 0; ready = false;
        }

        private bool WaitReady(bool expected) {
            int poll = 0;
            while (poll < maximumPolls) {
                long status = io.Read32(28);
                if ((status / 2) % 2 != 0) { return false; } // CSTS.CFS
                if (Nvme.IsReady(status) == expected) { return true; }
                io.Pause(); poll = poll + 1;
            }
            return false;
        }

        private bool Submit(bool admin, byte[] command) {
            int sqPage = 0; int cqPage = 1; int queueId = 0;
            int tail = adminTail; int head = adminHead; int phase = adminPhase;
            if (!admin) {
                sqPage = 2; cqPage = 3; queueId = 1;
                tail = ioTail; head = ioHead; phase = ioPhase;
            }
            int commandId = nextCommandId;
            nextCommandId = (nextCommandId + 1) % 65536;
            command[2] = (byte)(commandId % 256);
            command[3] = (byte)(commandId / 256);
            io.WriteDma(sqPage, tail * 64, command, 64);
            tail = (tail + 1) % 2;
            io.Write32(4096 + 2 * queueId * stride, tail);

            byte[] completion = new byte[16];
            int poll = 0;
            while (poll < maximumPolls) {
                if ((io.Read32(28) / 2) % 2 != 0) { return false; }
                io.ReadDma(cqPage, head * 16, completion, 16);
                int status = completion[14] + completion[15] * 256;
                if (status % 2 == phase) {
                    int completedId = completion[12] + completion[13] * 256;
                    int completedQueue = completion[10] + completion[11] * 256;
                    head = (head + 1) % 2;
                    if (head == 0) { phase = 1 - phase; }
                    io.Write32(4096 + (2 * queueId + 1) * stride, head);
                    if (admin) { adminTail = tail; adminHead = head; adminPhase = phase; }
                    else { ioTail = tail; ioHead = head; ioPhase = phase; }
                    return completedId == commandId && completedQueue == queueId && status / 2 == 0;
                }
                io.Pause(); poll = poll + 1;
            }
            return false;
        }

        public bool Initialize() {
            if (io == null || maximumPolls < 1) { return false; }
            ready = false; sectorSize = 0; sectorCount = 0;
            adminTail = 0; adminHead = 0; adminPhase = 1;
            ioTail = 0; ioHead = 0; ioPhase = 1;
            nextCommandId = 1;
            long capLow = io.Read32(0);
            long capHigh = io.Read32(4);
            if (capLow % 65536 < 1 || (capHigh / 32) % 2 == 0 || (capHigh / 65536) % 16 != 0) { return false; }
            stride = Nvme.DoorbellStrideFromHigh(capHigh);
            if (stride == 0) { return false; }
            long[] pages = new long[5];
            int page = 0;
            while (page < 5) {
                pages[page] = io.PhysicalPage(page);
                if (pages[page] < 4096 || pages[page] % 4096 != 0) { return false; }
                int previous = 0;
                while (previous < page) {
                    if (pages[previous] == pages[page]) { return false; }
                    previous = previous + 1;
                }
                page = page + 1;
            }
            byte[] zeroPage = new byte[4096];
            page = 0;
            while (page < 5) { io.WriteDma(page, 0, zeroPage, 4096); page = page + 1; }
            long configuration = io.Read32(20);
            io.Write32(20, configuration - configuration % 2);
            if (!WaitReady(false)) { return false; }
            io.Write32(36, 65537); // two entries in each admin queue
            io.Write32(40, pages[0] % U32Base());
            io.Write32(44, pages[0] / U32Base());
            io.Write32(48, pages[1] % U32Base());
            io.Write32(52, pages[1] / U32Base());
            io.Write32(20, Nvme.ControllerConfiguration() + 1);
            if (!WaitReady(true)) { return false; }

            byte[] command = new byte[64];
            byte[] identify = new byte[4096];
            if (!Nvme.BuildIdentify(command, 0, 0, true, pages[4]) || !Submit(true, command)) { return false; }
            io.ReadDma(4, 0, identify, 4096);
            if (identify[516] == 0 && identify[517] == 0 && identify[518] == 0 && identify[519] == 0) { return false; }
            if (!Nvme.BuildIdentify(command, 0, 1, false, pages[4]) || !Submit(true, command)) { return false; }
            io.ReadDma(4, 0, identify, 4096);
            int activeFormat = identify[26] % 16;
            int formatOffset = 128 + activeFormat * 4;
            if (identify[formatOffset] != 0 || identify[formatOffset + 1] != 0) { return false; }
            sectorSize = Nvme.NamespaceSectorSize(identify);
            sectorCount = Nvme.NamespaceSectorCount(identify);
            if (sectorSize == 0 || sectorCount == 0) { return false; }

            command = new byte[64];
            command[0] = 5; // Create I/O Completion Queue
            command[24] = (byte)(pages[3] % 256);
            long address = pages[3] / 256;
            int addressByte = 25;
            while (addressByte < 32) { command[addressByte] = (byte)(address % 256); address = address / 256; addressByte = addressByte + 1; }
            command[40] = 1; command[42] = 1; command[44] = 1; // QID=1, QSIZE=1, PC=1
            if (!Submit(true, command)) { return false; }
            command = new byte[64];
            command[0] = 1; // Create I/O Submission Queue
            command[24] = (byte)(pages[2] % 256);
            address = pages[2] / 256; addressByte = 25;
            while (addressByte < 32) { command[addressByte] = (byte)(address % 256); address = address / 256; addressByte = addressByte + 1; }
            command[40] = 1; command[42] = 1; command[44] = 1; command[46] = 1; // CQID=1
            if (!Submit(true, command)) { return false; }
            ready = true;
            return true;
        }

        public int SectorSize() { return sectorSize; }
        public long SectorCount() { return sectorCount; }
        public bool Flush() { return ready; } // read-only bootstrap

        public bool Read(long lba, int sectors, byte[] destination) {
            if (!ready || lba < 0 || sectors < 1 || destination == null ||
                lba >= sectorCount || sectors > sectorCount - lba || sectors > destination.Length / sectorSize) { return false; }
            byte[] staged = new byte[sectors * sectorSize];
            byte[] page = new byte[4096];
            int remaining = sectors;
            int copied = 0;
            while (remaining > 0) {
                int blocks = 4096 / sectorSize;
                if (blocks > remaining) { blocks = remaining; }
                byte[] command = new byte[64];
                if (!Nvme.BuildRead(command, 0, 1, io.PhysicalPage(4), lba, blocks, sectorSize) ||
                    !Submit(false, command)) { ready = false; return false; }
                io.ReadDma(4, 0, page, blocks * sectorSize);
                int i = 0;
                while (i < blocks * sectorSize) { staged[copied + i] = page[i]; i = i + 1; }
                copied = copied + blocks * sectorSize;
                lba = lba + blocks;
                remaining = remaining - blocks;
            }
            int byteIndex = 0;
            while (byteIndex < copied) { destination[byteIndex] = staged[byteIndex]; byteIndex = byteIndex + 1; }
            return true;
        }
    }
}
