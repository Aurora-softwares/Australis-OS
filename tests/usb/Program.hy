using Australis.Kernel.Usb;

public class MockPci : IPciConfig {
    public long Read32(int bus, int device, int function, int offset) {
        if (bus == 0 && device == 5 && function == 0) {
            if (offset == 0) { return 4660; }
            if (offset == 8) { return 201535489; } // revision 1, class 0C:03:30
            if (offset == 12) { return 0; }
        }
        return 65535;
    }
}

public class MockXhci : IXhciRegisters {
    private int command;
    private int pauses;

    public MockXhci() { command = 1; pauses = 0; }
    public int Read32(int offset) {
        if (offset == 32) { return command; }
        if (offset == 36) { if (pauses > 0) { return 1; } return 0; }
        return 0;
    }
    public void Write32(int offset, int value) { if (offset == 32) { command = value; } }
    public void Pause() { pauses = pauses + 1; if (command == 2) { command = 0; } }
    public int Pauses() { return pauses; }
}

public class MockBulk : IUsbBulkTransport {
    private int stage;
    private int resets;
    private bool failData;
    private int commandStatus;
    public MockBulk(bool fail) { stage = 0; resets = 0; failData = fail; commandStatus = 0; }
    public void SetCommandStatus(int value) { commandStatus = value; }
    public int BulkOut(byte[] data, int length) {
        if (stage != 0 || length != 31 || data[0] != 85 || data[15] != 40) { return -1; }
        stage = 1;
        return length;
    }
    public int BulkIn(byte[] data, int length) {
        if (stage == 1) {
            if (failData) { return -1; }
            int i = 0;
            while (i < length) { data[i] = 42; i = i + 1; }
            stage = 2;
            return length;
        }
        if (stage == 2 && length == 13) {
            data[0] = 85; data[1] = 83; data[2] = 66; data[3] = 83; data[4] = 9; data[12] = (byte)commandStatus;
            stage = 3;
            return 13;
        }
        return -1;
    }
    public void ResetRecovery() { resets = resets + 1; }
    public int Resets() { return resets; }
}

public class Program {
    public static int Main() {
        if (PciUsb.FindXhci(new MockPci()) != 40) { return 1; }
        if (!PciUsb.HasMemoryBar(4096) || PciUsb.HasMemoryBar(1)) { return 2; }
        MockXhci controller = new MockXhci();
        if (!XhciController.StopAndReset(controller, 32) || controller.Pauses() == 0) { return 3; }

        byte[] config = new byte[32];
        config[0] = 9; config[1] = 2; config[2] = 32; config[4] = 1;
        config[9] = 9; config[10] = 4; config[13] = 2;
        config[14] = 8; config[15] = 6; config[16] = 80;
        config[18] = 7; config[19] = 5; config[20] = 129; config[21] = 2;
        config[25] = 7; config[26] = 5; config[27] = 2; config[28] = 2;
        int interfaceOffset = UsbDescriptors.FindInterface(config, 32, 8, 6, 80);
        if (interfaceOffset != 9) { return 4; }
        if (UsbDescriptors.FindEndpoint(config, 32, interfaceOffset, 1, 2) != 129) { return 5; }
        if (UsbDescriptors.FindEndpoint(config, 32, interfaceOffset, 0, 2) != 2) { return 6; }
        config[18] = 0;
        if (UsbDescriptors.FindEndpoint(config, 32, interfaceOffset, 1, 2) != -1) { return 7; }

        byte[] cdb = new byte[10];
        if (!UsbMassStorage.BuildRead10(cdb, 305419896, 2)) { return 8; }
        if (cdb[0] != 40 || cdb[2] != 18 || cdb[3] != 52 || cdb[4] != 86 || cdb[5] != 120 || cdb[8] != 2) { return 9; }
        byte[] cbw = new byte[31];
        if (!UsbMassStorage.BuildCbw(cbw, 7, 1024, true, 0, cdb, 10)) { return 10; }
        if (cbw[0] != 85 || cbw[1] != 83 || cbw[2] != 66 || cbw[3] != 67 || cbw[4] != 7 || cbw[12] != 128 || cbw[14] != 10 || cbw[15] != 40) { return 11; }
        byte[] csw = new byte[13];
        csw[0] = 85; csw[1] = 83; csw[2] = 66; csw[3] = 83; csw[4] = 7;
        if (UsbMassStorage.CheckCsw(csw, 13, 7) != 0) { return 12; }
        if (UsbMassStorage.CheckCsw(csw, 13, 8) != -1) { return 13; }
        byte[] blocks = new byte[512];
        MockBulk bulk = new MockBulk(false);
        if (!UsbMassStorage.ReadBlocks(bulk, 0, 0, 1, 512, 9, blocks) || blocks[0] != 42 || bulk.Resets() != 0) { return 16; }
        MockBulk failedBulk = new MockBulk(true);
        if (UsbMassStorage.ReadBlocks(failedBulk, 0, 0, 1, 512, 9, blocks) || failedBulk.Resets() != 1) { return 17; }
        MockBulk rejectedCommand = new MockBulk(false);
        rejectedCommand.SetCommandStatus(1);
        if (UsbMassStorage.ReadBlocks(rejectedCommand, 0, 0, 1, 512, 9, blocks) || rejectedCommand.Resets() != 0) { return 19; }

        byte[] before = new byte[8]; byte[] after = new byte[8];
        after[2] = 4;
        if (UsbHidBoot.NewKey(before, after) != 4 || UsbHidBoot.NewKey(after, after) != 0) { return 14; }
        if (UsbHidBoot.UsAscii(4, 0) != 97 || UsbHidBoot.UsAscii(4, 2) != 65 ||
            UsbHidBoot.UsAscii(39, 0) != 48 || UsbHidBoot.UsAscii(40, 0) != 13) { return 18; }
        byte[] mouse = new byte[3]; mouse[0] = 1; mouse[1] = 254; mouse[2] = 3;
        if (UsbHidBoot.MouseButtons(mouse) != 1 || UsbHidBoot.MouseX(mouse) != -2 || UsbHidBoot.MouseY(mouse) != 3) { return 15; }
        System.Console.WriteLine("Australis USB protocol tests passed");
        return 0;
    }
}
