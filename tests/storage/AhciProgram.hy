using Australis.Kernel.Storage;

public class MockAhci : IAhciRegisters {
    private long[] values;
    private int pauses;
    public MockAhci() { values = new long[4096]; pauses = 0; }
    public long Read32(int offset) { return values[offset / 4]; }
    public void Write32(int offset, long value) { values[offset / 4] = value; }
    public void Pause() {
        pauses = pauses + 1;
        // Hardware clears CR and FR after ST/FRE are cleared. Model that
        // acknowledgement when the bounded reset path polls PxCMD.
        if (values[70] % 2 == 0 && (values[70] / 16) % 2 == 0) {
            values[70] = values[70] - (values[70] / 16384 % 2) * 16384 - (values[70] / 32768 % 2) * 32768;
        }
    }
    public int Pauses() { return pauses; }
}

public class Program {
    public static int Main() {
        MockAhci registers = new MockAhci();
        registers.Write32(12, 5);
        registers.Write32(256 + 36, 257); registers.Write32(256 + 40, 259);
        if (Ahci.FindActiveSataPort(registers) != 0 || !Ahci.IsActiveSata(257, 259) || Ahci.IsActiveSata(235, 259)) { return 1; }
        registers.Write32(256 + 24, 49169);
        if (!Ahci.StopCommandEngine(registers, 0, 4) || registers.Read32(280) != 0) { return 2; }
        if (!Ahci.StartCommandEngine(registers, 0, 4) || registers.Read32(280) != 17) { return 3; }

        byte[] header = new byte[32]; byte[] table = new byte[144];
        if (!Ahci.BuildIdentify(header, table, 8192, 12288) || header[0] != 5 || header[2] != 1 ||
            table[0] != 39 || table[1] != 128 || table[2] != 236 || table[128] != 0 || table[129] != 48 ||
            table[140] != 255 || table[141] != 1 || table[143] != 128) { return 4; }
        long lba = 1;
        int lbaByte = 0;
        while (lbaByte < 5) { lba = lba * 256; lbaByte = lbaByte + 1; }
        lba = lba + 15365;
        if (!Ahci.BuildReadDmaExt(header, table, 8192, 16384, lba, 2, 512)) { return 5; }
        if (table[2] != 37 || table[7] != 64) { return 51; }
        if (table[4] != 5 || table[5] != 60 || table[8] != 0 || table[9] != 0 || table[10] != 1) { return 52; }
        if (table[12] != 2) { return 53; }
        if (table[140] != 255 || table[141] != 3 || table[143] != 128) { return 54; }
        if (Ahci.BuildReadDmaExt(header, table, 0, 0, -1, 1, 512) || Ahci.BuildReadDmaExt(header, table, 0, 0, 0, 1, 768)) { return 6; }

        byte[] identify = new byte[512];
        identify[166] = 0; identify[167] = 4;
        identify[200] = 120; identify[201] = 86; identify[202] = 52; identify[203] = 18;
        identify[204] = 2;
        if (!Ahci.SupportsLba48(identify)) { return 71; }
        long expectedCapacity = 2;
        expectedCapacity = expectedCapacity * 65536 * 65536 + 305419896;
        if (Ahci.IdentifySectorCount(identify) != expectedCapacity) { return 7; }
        identify[166] = 0; identify[167] = 0; identify[120] = 3; identify[122] = 1;
        if (Ahci.IdentifySectorCount(identify) != 65539) { return 8; }
        System.Console.WriteLine("Australis AHCI protocol tests passed");
        return 0;
    }
}
