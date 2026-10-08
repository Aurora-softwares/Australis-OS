using Australis.Kernel.Storage;

public class MockNvmeController : INvmeControllerIo {
    private byte[] pages;
    private long configuration;
    private int status;
    private int[] completionTail;
    private int[] completionPhase;
    private int commands;
    private bool failRead;
    private bool suppressCompletion;

    public MockNvmeController() {
        pages = new byte[20480];
        configuration = 0; status = 0;
        completionTail = new int[2]; completionPhase = new int[2];
        completionPhase[0] = 1; completionPhase[1] = 1;
        commands = 0; failRead = false; suppressCompletion = false;
    }

    public void FailRead() { failRead = true; }
    public void SuppressCompletion() { suppressCompletion = true; }
    public int Commands() { return commands; }
    public long Read32(int offset) {
        if (offset == 0) { return 1; } // MQES=1, queue depth two
        if (offset == 4) { return 32; } // CSS.NVM, DSTRD=0, MPSMIN=0
        if (offset == 20) { return configuration; }
        if (offset == 28) { return status; }
        return 0;
    }
    public void Write32(int offset, long value) {
        if (offset == 20) { configuration = value; status = (int)(value % 2); return; }
        if (offset == 4096 || offset == 4104) {
            int queue = 0;
            if (offset == 4104) { queue = 1; }
            int slot = ((int)value + 1) % 2;
            int sqPage = queue * 2;
            int cqPage = sqPage + 1;
            byte[] command = new byte[64];
            int i = 0;
            while (i < 64) { command[i] = pages[sqPage * 4096 + slot * 64 + i]; i = i + 1; }
            commands = commands + 1;
            if (queue == 0 && command[0] == 6) {
                i = 0; while (i < 4096) { pages[16384 + i] = 0; i = i + 1; }
                if (command[40] == 1) { pages[16384 + 516] = 1; }
                else { pages[16384] = 128; pages[16384 + 130] = 9; }
            }
            if (queue == 1 && command[0] == 2 && !failRead) {
                long lba = command[40] + command[41] * 256 + command[42] * 65536 + command[43] * 16777216;
                int blocks = command[48] + command[49] * 256 + 1;
                i = 0;
                while (i < blocks * 512) { pages[16384 + i] = (byte)(lba + i / 512); i = i + 1; }
            }
            if (suppressCompletion) { return; }
            int completion = completionTail[queue] * 16;
            pages[cqPage * 4096 + completion + 10] = (byte)queue;
            pages[cqPage * 4096 + completion + 12] = command[2];
            pages[cqPage * 4096 + completion + 13] = command[3];
            int completionStatus = completionPhase[queue];
            if (failRead && queue == 1) { completionStatus = completionStatus + 2; }
            pages[cqPage * 4096 + completion + 14] = (byte)completionStatus;
            pages[cqPage * 4096 + completion + 15] = 0;
            completionTail[queue] = (completionTail[queue] + 1) % 2;
            if (completionTail[queue] == 0) { completionPhase[queue] = 1 - completionPhase[queue]; }
        }
    }
    public long PhysicalPage(int index) { return 1048576 + index * 4096; }
    public void WriteDma(int page, int offset, byte[] source, int count) {
        int i = 0; while (i < count) { pages[page * 4096 + offset + i] = source[i]; i = i + 1; }
    }
    public void ReadDma(int page, int offset, byte[] destination, int count) {
        int i = 0; while (i < count) { destination[i] = pages[page * 4096 + offset + i]; i = i + 1; }
    }
    public void Pause() { }
}

public class Program {
    public static int Main() {
        MockNvmeController mock = new MockNvmeController();
        NvmeController controller = new NvmeController(mock, 32);
        if (!controller.Initialize() || controller.SectorSize() != 512 || controller.SectorCount() != 128) { return 1; }
        BlockDevice disk = new BlockDevice(controller);
        byte[] data = new byte[5120];
        if (disk.Read(7, 10, data) != BlockStatus.Ok() || data[0] != 7 || data[4096] != 15 || mock.Commands() != 6) { return 2; }
        if (disk.Read(127, 2, data) != BlockStatus.OutOfRange()) { return 3; }
        mock.FailRead();
        byte[] unchanged = new byte[512]; unchanged[0] = 99;
        if (disk.Read(1, 1, unchanged) != BlockStatus.IoFailure() || unchanged[0] != 99) { return 4; }
        if (disk.Read(1, 1, unchanged) != BlockStatus.IoFailure()) { return 5; }
        MockNvmeController stuck = new MockNvmeController(); stuck.SuppressCompletion();
        if (new NvmeController(stuck, 4).Initialize()) { return 6; }
        System.Console.WriteLine("Australis NVMe controller tests passed");
        return 0;
    }
}
