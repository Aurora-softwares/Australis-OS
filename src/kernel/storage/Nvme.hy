namespace Australis.Kernel.Storage {
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
            long shiftedCapabilities = capabilities;
            int shift = 0;
            while (shift < 32) { shiftedCapabilities = shiftedCapabilities / 2; shift = shift + 1; }
            int strideExponent = (int)(shiftedCapabilities % 16);
            if (strideExponent < 0 || strideExponent > 7) { return 0; }
            int stride = 4;
            int i = 0;
            while (i < strideExponent) { stride = stride * 2; i = i + 1; }
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
}
