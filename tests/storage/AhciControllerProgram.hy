using Australis.Kernel.Storage;

public class MockAhciControllerIo : IAhciControllerIo {
    private byte[] dma;
    private byte[] disk;
    private long command;
    private long interruptStatus;
    private int readCommands;
    private int writeCommands;
    private int flushCommands;
    private bool failWrite;
    private bool failFlush;
    private bool timeoutWrite;
    private bool timeoutFlush;
    private bool pendingCommand;
    private int failReadCommand;
    private int shortReadCommand;
    private bool stuckBusy;
    private int pauses;
    private bool interruptMode;
    private long epoch;
    private int pendingDelay;
    private int configuredDelay;
    private bool failAllReads;

    public MockAhciControllerIo() {
        dma = new byte[4 * 4096]; disk = new byte[64 * 512];
        int block = 0;
        while (block < 64) {
            int byteIndex = 0;
            while (byteIndex < 512) {
                disk[block * 512 + byteIndex] = (byte)block;
                byteIndex = byteIndex + 1;
            }
            block = block + 1;
        }
        command = 17; interruptStatus = 0;
        readCommands = 0; failReadCommand = 0; shortReadCommand = 0; stuckBusy = false; pauses = 0;
        writeCommands = 0; flushCommands = 0; failWrite = false; failFlush = false;
        timeoutWrite = false; timeoutFlush = false; pendingCommand = false;
        interruptMode = false; epoch = 0; pendingDelay = -1; configuredDelay = 0; failAllReads = false;
    }
    public void SetFailReadCommand(int number) { failReadCommand = number; }
    public void SetShortReadCommand(int number) { shortReadCommand = number; }
    public void SetStuckBusy(bool value) { stuckBusy = value; }
    public void SetFailAllReads(bool value) { failAllReads = value; }
    public void SetFailWrite(bool value) { failWrite = value; }
    public void SetFailFlush(bool value) { failFlush = value; }
    public void SetTimeoutWrite(bool value) { timeoutWrite = value; }
    public void SetTimeoutFlush(bool value) { timeoutFlush = value; }
    public void EnableDelayedInterrupts(int pauseCount) { interruptMode = true; configuredDelay = pauseCount; }
    public int ReadCommands() { return readCommands; }
    public int WriteCommands() { return writeCommands; }
    public int FlushCommands() { return flushCommands; }
    public int Pauses() { return pauses; }

    public long Read32(int offset) {
        if (offset == 0) { long high = 65536; return high * 32768; } // 64-bit addresses supported
        if (offset == 4) { long high = 65536; return high * 32768; }
        if (offset == 12) { return 1; }
        if (offset == 256 + 24) { return command; }
        if (offset == 256 + 36) { return 257; }
        if (offset == 256 + 40) { return 259; }
        if (offset == 256 + 32) { if (stuckBusy) { return 128; } return 0; }
        if (offset == 256 + 16) { return interruptStatus; }
        if (offset == 256 + 56) { if (pendingCommand) { return 1; } return 0; }
        return 0;
    }

    public void Write32(int offset, long value) {
        if (offset == 256 + 24) { command = value; return; }
        if (offset == 256 + 16) { interruptStatus = 0; return; }
        if (offset != 256 + 56 || value != 1) { return; }
        int opcode = dma[2 * 4096 + 2];
        pendingCommand = false;
        if (opcode == 236) {
            dma[3 * 4096 + 167] = 4; // LBA48 supported
            dma[3 * 4096 + 200] = 64; // 64 sectors
            dma[0 * 4096 + 4] = 0; dma[0 * 4096 + 5] = 2; // PRDBC = 512
            return;
        }
        if (opcode == 234) {
            flushCommands = flushCommands + 1;
            if (timeoutFlush) { pendingCommand = true; return; }
            if (failFlush) { interruptStatus = 1073741824; return; }
            dma[0 * 4096 + 4] = 0; dma[0 * 4096 + 5] = 0;
            return;
        }
        if (opcode != 37 && opcode != 53) { interruptStatus = 1073741824; return; }
        if (opcode == 37) {
            readCommands = readCommands + 1;
            if (readCommands == failReadCommand || failAllReads) {
                interruptStatus = 1073741824; return;
            }
        } else {
            writeCommands = writeCommands + 1;
            if (timeoutWrite) { pendingCommand = true; return; }
            if (failWrite) { interruptStatus = 1073741824; return; }
        }
        long lba = dma[2 * 4096 + 4] + dma[2 * 4096 + 5] * 256 +
            dma[2 * 4096 + 6] * 65536 + dma[2 * 4096 + 8] * 16777216;
        int blocks = dma[2 * 4096 + 12] + dma[2 * 4096 + 13] * 256;
        int transferred = blocks * 512;
        if (opcode == 37 && readCommands == shortReadCommand) { transferred = transferred - 1; }
        dma[0 * 4096 + 4] = (byte)(transferred % 256);
        dma[0 * 4096 + 5] = (byte)(transferred / 256);
        int byteIndex = 0;
        while (byteIndex < blocks * 512) {
            int diskIndex = (int)(lba * 512) + byteIndex;
            if (opcode == 37) { dma[3 * 4096 + byteIndex] = disk[diskIndex]; }
            else { disk[diskIndex] = dma[3 * 4096 + byteIndex]; }
            byteIndex = byteIndex + 1;
        }
        if (interruptMode) { pendingDelay = configuredDelay; }
    }

    public long PhysicalPage(int index) { return 1048576 + index * 4096; }
    public void WriteDma(int page, int offset, byte[] source, int count) {
        int i = 0;
        while (i < count) { dma[page * 4096 + offset + i] = source[i]; i = i + 1; }
    }
    public void ReadDma(int page, int offset, byte[] destination, int count) {
        int i = 0;
        while (i < count) { destination[i] = dma[page * 4096 + offset + i]; i = i + 1; }
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
        MockAhciControllerIo io = new MockAhciControllerIo();
        AhciController controller = new AhciController(io, 100);
        if (!controller.Initialize() || controller.SectorSize() != 512 ||
            controller.SectorCount() != 64 || !controller.Flush()) { return 1; }
        byte[] data = new byte[10 * 512];
        if (!controller.Read(3, 10, data) || io.ReadCommands() != 2 ||
            data[0] != 3 || data[7 * 512] != 10 || data[8 * 512] != 11 ||
            data[9 * 512] != 12) { return 2; }
        if (controller.Read(63, 2, data) || io.ReadCommands() != 2) { return 3; }
        BlockDevice writable = new BlockDevice(controller);
        byte[] payload = new byte[10 * 512];
        int fill = 0;
        while (fill < payload.Length) { payload[fill] = (byte)(fill % 251); fill = fill + 1; }
        if (writable.Write(20, 10, payload) != BlockStatus.Ok() ||
            io.WriteCommands() != 2 || writable.Flush() != BlockStatus.Ok() ||
            io.FlushCommands() != 2) { return 31; }
        byte[] roundTrip = new byte[payload.Length];
        if (writable.Read(20, 10, roundTrip) != BlockStatus.Ok()) { return 32; }
        int check = 0;
        while (check < payload.Length) {
            if (roundTrip[check] != payload[check]) { return 33; }
            check = check + 1;
        }
        MockAhciControllerIo writeFailureIo = new MockAhciControllerIo();
        AhciController writeFailure = new AhciController(writeFailureIo, 16);
        if (!writeFailure.Initialize()) { return 34; }
        writeFailureIo.SetFailWrite(true);
        if (writeFailure.Write(4, 1, new byte[512]) ||
            writeFailureIo.WriteCommands() != 1 || writeFailure.Flush() ||
            writeFailure.RetryCount() != 0) { return 35; }
        writeFailureIo.SetFailWrite(false);
        byte[] recoveredPayload = new byte[512]; recoveredPayload[0] = 73;
        byte[] recoveredData = new byte[512];
        if (!writeFailure.Initialize() || !writeFailure.Write(4, 1, recoveredPayload) ||
            !writeFailure.Flush() || !writeFailure.Read(4, 1, recoveredData) ||
            recoveredData[0] != 73 || writeFailureIo.WriteCommands() != 2) { return 47; }
        MockAhciControllerIo flushFailureIo = new MockAhciControllerIo();
        AhciController flushFailure = new AhciController(flushFailureIo, 16);
        if (!flushFailure.Initialize()) { return 36; }
        flushFailureIo.SetFailFlush(true);
        if (flushFailure.Flush() || flushFailureIo.FlushCommands() != 1) { return 37; }
        flushFailureIo.SetFailFlush(false);
        if (!flushFailure.Initialize() || !flushFailure.Write(5, 1, recoveredPayload) ||
            !flushFailure.Flush() || flushFailureIo.FlushCommands() != 2) { return 48; }
        MockAhciControllerIo writeTimeoutIo = new MockAhciControllerIo();
        AhciController writeTimeout = new AhciController(writeTimeoutIo, 4);
        if (!writeTimeout.Initialize()) { return 38; }
        writeTimeoutIo.SetTimeoutWrite(true);
        if (writeTimeout.Write(4, 1, new byte[512]) || writeTimeout.LastError() != 5 ||
            writeTimeout.RecoveryState() != 4 || writeTimeout.RetryCount() != 0 ||
            writeTimeoutIo.WriteCommands() != 1 ||
            writeTimeout.Write(4, 1, new byte[512]) || writeTimeout.Flush() ||
            writeTimeoutIo.WriteCommands() != 1) { return 39; }
        writeTimeoutIo.SetTimeoutWrite(false);
        if (!writeTimeout.Initialize() || !writeTimeout.Write(4, 1, recoveredPayload) ||
            !writeTimeout.Flush() || writeTimeoutIo.WriteCommands() != 2) { return 49; }
        MockAhciControllerIo flushTimeoutIo = new MockAhciControllerIo();
        AhciController flushTimeout = new AhciController(flushTimeoutIo, 4);
        if (!flushTimeout.Initialize()) { return 40; }
        flushTimeoutIo.SetTimeoutFlush(true);
        if (flushTimeout.Flush() || flushTimeout.LastError() != 5 ||
            flushTimeout.RecoveryState() != 4 || flushTimeout.RetryCount() != 0 ||
            flushTimeoutIo.FlushCommands() != 1 || flushTimeout.Flush() ||
            flushTimeoutIo.FlushCommands() != 1) { return 46; }
        flushTimeoutIo.SetTimeoutFlush(false);
        if (!flushTimeout.Initialize() || !flushTimeout.Flush() ||
            flushTimeoutIo.FlushCommands() != 2) { return 50; }

        MockAhciControllerIo failedIo = new MockAhciControllerIo();
        AhciController failed = new AhciController(failedIo, 100);
        if (!failed.Initialize()) { return 4; }
        failedIo.SetFailReadCommand(2);
        byte[] unchanged = new byte[10 * 512]; unchanged[0] = 91; unchanged[9 * 512] = 92;
        if (!failed.Read(3, 10, unchanged) || failedIo.ReadCommands() <= 2 ||
            failed.RetryCount() != 1 || failed.RecoveryState() != 0 ||
            unchanged[0] != 3 || unchanged[9 * 512] != 12 || !failed.Flush()) { return 5; }

        MockAhciControllerIo shortIo = new MockAhciControllerIo();
        AhciController shortController = new AhciController(shortIo, 100);
        if (!shortController.Initialize()) { return 7; }
        shortIo.SetShortReadCommand(1);
        byte[] shortDestination = new byte[512]; shortDestination[0] = 77;
        if (!shortController.Read(3, 1, shortDestination) || shortDestination[0] != 3 ||
            !shortController.Flush()) { return 8; }

        MockAhciControllerIo busyIo = new MockAhciControllerIo();
        busyIo.SetStuckBusy(true);
        if (new AhciController(busyIo, 3).Initialize() || busyIo.Pauses() != 3) { return 6; }
        MockAhciControllerIo delayedIo = new MockAhciControllerIo();
        AhciController delayed = new AhciController(delayedIo, 16);
        if (!delayed.Initialize()) { return 9; }
        delayedIo.EnableDelayedInterrupts(3);
        byte[] delayedData = new byte[512];
        if (!delayed.Read(4, 1, delayedData) || delayedData[0] != 4 ||
            delayedIo.CompletionEpoch() == 0 || delayedIo.Pauses() < 4) { return 10; }
        MockAhciControllerIo exhaustedIo = new MockAhciControllerIo();
        AhciController exhausted = new AhciController(exhaustedIo, 8);
        if (!exhausted.Initialize()) { return 11; }
        exhaustedIo.SetFailAllReads(true);
        byte[] untouched = new byte[512]; untouched[0] = 61;
        if (exhausted.Read(2, 1, untouched) || untouched[0] != 61 ||
            exhausted.RetryCount() != 1 || exhausted.RecoveryState() != 4 ||
            exhausted.LastError() != 2) { return 12; }
        MockAhciControllerIo timedOutIo = new MockAhciControllerIo();
        AhciController timedOut = new AhciController(timedOutIo, 3);
        if (!timedOut.Initialize()) { return 13; }
        timedOutIo.SetStuckBusy(true);
        byte[] timedOutData = new byte[512]; timedOutData[0] = 17;
        if (timedOut.Read(1, 1, timedOutData) || timedOutData[0] != 17 ||
            timedOut.RecoveryState() != 4 || timedOut.RetryCount() != 1 ||
            timedOut.LastError() != 1) { return 14; }
        System.Console.WriteLine("Australis AHCI controller tests passed");
        return 0;
    }
}
