namespace Australis.Kernel.Storage {
    // AHCI ABAR is mapped uncached; the bootstrap DMA reservation provides
    // command list, received FIS, command table, and transfer pages.
    public class NativeAhciIo : IAhciControllerIo {
        private long registers;
        private long dmaBase;

        public NativeAhciIo(long bootInfo) {
            registers = System.Kernel.Memory.Read64(bootInfo + 248);
            dmaBase = System.Kernel.Memory.Read64(bootInfo + 280);
        }

        public long Read32(int offset) {
            if (registers == 0 || offset < 0 || offset >= 65536) { return 0; }
            return System.Kernel.Memory.Read32(registers + offset);
        }

        public void Write32(int offset, long value) {
            if (registers != 0 && offset >= 0 && offset < 65536) {
                System.Kernel.Memory.Write32(registers + offset, value);
            }
        }

        public long PhysicalPage(int index) {
            if (dmaBase < 4096 || index < 0 || index >= 4) { return 0; }
            return dmaBase + index * 4096;
        }

        public void WriteDma(int page, int offset, byte[] source, int count) {
            if (page < 0 || page >= 4 || offset < 0 || count < 0 ||
                count > 4096 - offset || source == null || source.Length < count) { return; }
            long address = PhysicalPage(page) + offset;
            int i = 0;
            while (i < count) {
                System.Kernel.Memory.Write8(address + i, source[i]);
                i = i + 1;
            }
        }

        public void ReadDma(int page, int offset, byte[] destination, int count) {
            if (page < 0 || page >= 4 || offset < 0 || count < 0 ||
                count > 4096 - offset || destination == null || destination.Length < count) { return; }
            long address = PhysicalPage(page) + offset;
            int i = 0;
            while (i < count) {
                destination[i] = (byte)System.Kernel.Memory.Read8(address + i);
                i = i + 1;
            }
        }

        public void Pause() { System.Kernel.Cpu.Pause(); }
    }
}
