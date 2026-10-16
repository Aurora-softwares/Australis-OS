using Australis.Kernel.Storage;

public class MockNvmeController : INvmeControllerIo {
    private byte[] pages;
    private byte[] disk;
    private long configuration;
    private int status;
    private int[] completionTail;
    private int[] completionPhase;
    private int commands;
    private bool failRead;
    private int failNextReads;
    private bool failWrite;
    private bool silentlyDropWrite;
    private bool failFlush;
    private int writes;
    private int flushes;
    private bool suppressCompletion;
    private bool interruptMode;
    private int pendingDelay;
    private int configuredDelay;
    private int pauses;
    private long epoch;
    private bool highCid;

    public MockNvmeController() {
        pages = new byte[20480]; disk = new byte[128 * 512];
        int block = 0;
        while (block < 128) {
            int byteIndex = 0;
            while (byteIndex < 512) {
                disk[block * 512 + byteIndex] = (byte)block;
                byteIndex = byteIndex + 1;
            }
            block = block + 1;
        }
        configuration = 0; status = 0;
        completionTail = new int[2]; completionPhase = new int[2];
        completionPhase[0] = 1; completionPhase[1] = 1;
        commands = 0; failRead = false; failNextReads = 0;
        failWrite = false; silentlyDropWrite = false; failFlush = false;
        writes = 0; flushes = 0; suppressCompletion = false;
        interruptMode = false; pendingDelay = -1; configuredDelay = 0; pauses = 0; epoch = 0;
    }

    public void FailRead() { failRead = true; }
    public void FailNextRead() { failNextReads = 1; }
    public void FailWrite() { failWrite = true; }
    public void AllowWrite() { failWrite = false; }
    public void SilentlyDropWrite() { silentlyDropWrite = true; }
    public void FailFlush() { failFlush = true; }
    public void AllowFlush() { failFlush = false; }
    public void SuppressCompletion() { suppressCompletion = true; }
    public void AllowCompletion() { suppressCompletion = false; }
    public void EnableDelayedInterrupts(int pauseCount) { interruptMode = true; configuredDelay = pauseCount; }
    public int Pauses() { return pauses; }
    public int Commands() { return commands; }
    public int Writes() { return writes; }
    public int Flushes() { return flushes; }
    public bool SawHighCid() { return highCid; }
    public long Read32(int offset) {
        if (offset == 0) { return 1; } // MQES=1, queue depth two
        if (offset == 4) { return 32; } // CSS.NVM, DSTRD=0, MPSMIN=0
        if (offset == 20) { return configuration; }
        if (offset == 28) { return status; }
        return 0;
    }
    public void Write32(int offset, long value) {
        if (offset == 20) {
            configuration = value; status = (int)(value % 2);
            if (status == 0) {
                completionTail[0] = 0; completionTail[1] = 0;
                completionPhase[0] = 1; completionPhase[1] = 1;
            }
            return;
        }
        if (offset == 4096 || offset == 4104) {
            int queue = 0;
            if (offset == 4104) { queue = 1; }
            int slot = ((int)value + 1) % 2;
            int sqPage = queue * 2;
            int cqPage = sqPage + 1;
            byte[] command = new byte[64];
            int i = 0;
            while (i < 64) { command[i] = pages[sqPage * 4096 + slot * 64 + i]; i = i + 1; }
            if (command[3] != 0) { highCid = true; }
            commands = commands + 1;
            if (queue == 0 && command[0] == 6) {
                i = 0; while (i < 4096) { pages[16384 + i] = 0; i = i + 1; }
                if (command[40] == 1) { pages[16384 + 516] = 1; }
                else { pages[16384] = 128; pages[16384 + 130] = 9; }
            }
            if (queue == 1 && command[0] == 0) { flushes = flushes + 1; }
            if (queue == 1 && command[0] == 1) { writes = writes + 1; }
            bool rejectRead = queue == 1 && command[0] == 2 &&
                (failRead || failNextReads > 0);
            if (rejectRead && failNextReads > 0) { failNextReads = failNextReads - 1; }
            if (queue == 1 && (command[0] == 1 || command[0] == 2)) {
                long lba = command[40] + command[41] * 256 + command[42] * 65536 + command[43] * 16777216;
                int blocks = command[48] + command[49] * 256 + 1;
                if ((command[0] == 2 && !rejectRead) || (command[0] == 1 && !failWrite)) {
                    i = 0;
                    while (i < blocks * 512) {
                        int diskIndex = (int)(lba * 512) + i;
                        if (command[0] == 2) { pages[16384 + i] = disk[diskIndex]; }
                        else if (!silentlyDropWrite) { disk[diskIndex] = pages[16384 + i]; }
                        i = i + 1;
                    }
                }
            }
            if (suppressCompletion) { return; }
            int completion = completionTail[queue] * 16;
            pages[cqPage * 4096 + completion + 10] = (byte)queue;
            pages[cqPage * 4096 + completion + 12] = command[2];
            pages[cqPage * 4096 + completion + 13] = command[3];
            int completionStatus = completionPhase[queue];
            if (queue == 1 && (rejectRead ||
                (failWrite && command[0] == 1) || (failFlush && command[0] == 0))) {
                completionStatus = completionStatus + 2;
            }
            pages[cqPage * 4096 + completion + 14] = (byte)completionStatus;
            pages[cqPage * 4096 + completion + 15] = 0;
            completionTail[queue] = (completionTail[queue] + 1) % 2;
            if (completionTail[queue] == 0) { completionPhase[queue] = 1 - completionPhase[queue]; }
            if (queue == 1 && interruptMode) { pendingDelay = configuredDelay; }
        }
    }
    public long PhysicalPage(int index) { return 1048576 + index * 4096; }
    public void WriteDma(int page, int offset, byte[] source, int count) {
        int i = 0; while (i < count) { pages[page * 4096 + offset + i] = source[i]; i = i + 1; }
    }
    public void ReadDma(int page, int offset, byte[] destination, int count) {
        int i = 0; while (i < count) { destination[i] = pages[page * 4096 + offset + i]; i = i + 1; }
    }
    public void Pause() {
        pauses = pauses + 1;
        if (pendingDelay >= 0) {
            if (pendingDelay == 0) { epoch = epoch + 1; pendingDelay = -1; }
            else { pendingDelay = pendingDelay - 1; }
        }
    }
    public long CompletionEpoch() { if (interruptMode) { return epoch; } return -1; }
    public long Deadline(int milliseconds) { return pauses + milliseconds; }
    public bool Expired(long deadline) { return pauses >= deadline; }
    public void ReportFailure(int cause, int state) { }
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
        byte[] payload = new byte[10 * 512];
        int fill = 0;
        while (fill < payload.Length) { payload[fill] = (byte)(fill % 239); fill = fill + 1; }
        if (disk.Write(20, 10, payload) != BlockStatus.Ok() || mock.Writes() != 2 ||
            disk.Flush() != BlockStatus.Ok() || mock.Flushes() != 1) { return 31; }
        byte[] roundTrip = new byte[payload.Length];
        if (disk.Read(20, 10, roundTrip) != BlockStatus.Ok()) { return 32; }
        int check = 0;
        while (check < payload.Length) {
            if (roundTrip[check] != payload[check]) { return 33; }
            check = check + 1;
        }
        MockNvmeController wrapMock = new MockNvmeController();
        NvmeController wrap = new NvmeController(wrapMock, 32);
        if (!wrap.Initialize()) { return 56; }
        byte[] wrapData = new byte[512]; int repeat = 0;
        while (repeat < 300) {
            if (!wrap.Read(1, 1, wrapData) || wrapData[0] != 1) { return 57; }
            repeat = repeat + 1;
        }
        if (wrapMock.SawHighCid()) { return 58; }
        MockNvmeController writeFailureMock = new MockNvmeController();
        NvmeController writeFailure = new NvmeController(writeFailureMock, 16);
        if (!writeFailure.Initialize()) { return 34; }
        writeFailureMock.FailWrite();
        if (writeFailure.Write(4, 1, new byte[512]) ||
            writeFailureMock.Writes() != 1 || writeFailure.Flush() ||
            writeFailure.RetryCount() != 0) { return 35; }
        writeFailureMock.AllowWrite();
        byte[] recoveredPayload = new byte[512]; recoveredPayload[0] = 73;
        byte[] recoveredData = new byte[512];
        if (!writeFailure.Initialize() || !writeFailure.Write(4, 1, recoveredPayload) ||
            !writeFailure.Flush() || !writeFailure.Read(4, 1, recoveredData) ||
            recoveredData[0] != 73 || writeFailureMock.Writes() != 2) { return 50; }
        MockNvmeController droppedMock = new MockNvmeController();
        NvmeController dropped = new NvmeController(droppedMock, 16);
        if (!dropped.Initialize()) { return 38; }
        droppedMock.SilentlyDropWrite();
        byte[] droppedPayload = new byte[512]; droppedPayload[0] = 91;
        if (dropped.Write(4, 1, droppedPayload) || dropped.LastError() != 7 ||
            dropped.Flush()) { return 39; }
        MockNvmeController flushFailureMock = new MockNvmeController();
        NvmeController flushFailure = new NvmeController(flushFailureMock, 16);
        if (!flushFailure.Initialize()) { return 36; }
        flushFailureMock.FailFlush();
        if (flushFailure.Flush() || flushFailureMock.Flushes() != 1 ||
            flushFailure.RecoveryState() != 4 || flushFailure.LastError() != 3 ||
            flushFailure.Flush() || flushFailureMock.Flushes() != 1) { return 37; }
        flushFailureMock.AllowFlush();
        if (!flushFailure.Initialize() || !flushFailure.Write(5, 1, recoveredPayload) ||
            !flushFailure.Flush() || flushFailureMock.Flushes() != 2) { return 51; }
        MockNvmeController writeTimeoutMock = new MockNvmeController();
        NvmeController writeTimeout = new NvmeController(writeTimeoutMock, 4);
        if (!writeTimeout.Initialize()) { return 46; }
        writeTimeoutMock.SuppressCompletion();
        if (writeTimeout.Write(4, 1, new byte[512]) || writeTimeout.LastError() != 1 ||
            writeTimeout.RecoveryState() != 4 || writeTimeout.RetryCount() != 0 ||
            writeTimeoutMock.Writes() != 1 ||
            writeTimeout.Write(4, 1, new byte[512]) || writeTimeout.Flush() ||
            writeTimeoutMock.Writes() != 1) { return 47; }
        writeTimeoutMock.AllowCompletion();
        if (!writeTimeout.Initialize() || !writeTimeout.Write(4, 1, recoveredPayload) ||
            !writeTimeout.Flush() || writeTimeoutMock.Writes() != 2) { return 52; }
        MockNvmeController flushTimeoutMock = new MockNvmeController();
        NvmeController flushTimeout = new NvmeController(flushTimeoutMock, 4);
        if (!flushTimeout.Initialize()) { return 48; }
        flushTimeoutMock.SuppressCompletion();
        if (flushTimeout.Flush() || flushTimeout.LastError() != 1 ||
            flushTimeout.RecoveryState() != 4 || flushTimeout.RetryCount() != 0 ||
            flushTimeoutMock.Flushes() != 1 || flushTimeout.Flush() ||
            flushTimeoutMock.Flushes() != 1) { return 49; }
        flushTimeoutMock.AllowCompletion();
        if (!flushTimeout.Initialize() || !flushTimeout.Flush() ||
            flushTimeoutMock.Flushes() != 2) { return 53; }
        MockNvmeController transientMock = new MockNvmeController();
        NvmeController transientRead = new NvmeController(transientMock, 16);
        if (!transientRead.Initialize()) { return 54; }
        transientMock.FailNextRead();
        byte[] transientData = new byte[512];
        if (!transientRead.Read(6, 1, transientData) || transientData[0] != 6 ||
            transientRead.RetryCount() != 1 || transientRead.RecoveryState() != 0) { return 55; }
        mock.FailRead();
        byte[] unchanged = new byte[512]; unchanged[0] = 99;
        if (disk.Read(1, 1, unchanged) != BlockStatus.IoFailure()) { return 41; }
        if (unchanged[0] != 99) { return 42; }
        if (controller.RetryCount() != 1) { return 43; }
        if (controller.RecoveryState() != 4) { return 44; }
        if (controller.LastError() == 0) { return 45; }
        if (disk.Read(1, 1, unchanged) != BlockStatus.IoFailure()) { return 5; }
        MockNvmeController stuck = new MockNvmeController(); stuck.SuppressCompletion();
        if (new NvmeController(stuck, 4).Initialize()) { return 6; }
        MockNvmeController delayedMock = new MockNvmeController();
        NvmeController delayed = new NvmeController(delayedMock, 16);
        if (!delayed.Initialize()) { return 7; }
        delayedMock.EnableDelayedInterrupts(3);
        byte[] delayedData = new byte[512];
        if (!delayed.Read(5, 1, delayedData) || delayedData[0] != 5 ||
            delayedMock.CompletionEpoch() == 0 || delayedMock.Pauses() < 4) { return 8; }
        MockNvmeController timedOutMock = new MockNvmeController();
        NvmeController timedOut = new NvmeController(timedOutMock, 4);
        if (!timedOut.Initialize()) { return 9; }
        timedOutMock.SuppressCompletion();
        byte[] timedOutData = new byte[512]; timedOutData[0] = 17;
        if (timedOut.Read(1, 1, timedOutData) || timedOutData[0] != 17 ||
            timedOut.RecoveryState() != 4 || timedOut.RetryCount() != 1 ||
            timedOut.LastError() != 1) { return 10; }
        System.Console.WriteLine("Australis NVMe controller tests passed");
        return 0;
    }
}
