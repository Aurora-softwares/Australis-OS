using Australis.Kernel.Storage;

public class Program {
    private static void Write32(byte[] bytes, int offset, long value) {
        int i = 0; while (i < 4) { bytes[offset + i] = (byte)(value % 256); value = value / 256; i = i + 1; }
    }
    private static void Write64(byte[] bytes, int offset, long value) {
        int i = 0; while (i < 8) { bytes[offset + i] = (byte)(value % 256); value = value / 256; i = i + 1; }
    }

    public static int Main() {
        byte[] mbr = new byte[512]; mbr[510] = 85; mbr[511] = 170;
        mbr[450] = 238; Write32(mbr, 454, 1); Write32(mbr, 458, 100);
        if (!Mbr.IsValid(mbr) || !Mbr.IsProtective(mbr)) { return 1; }
        Partition protective = Mbr.Entry(mbr, 0);
        if (!protective.Present() || protective.IsGpt() || protective.Type() != 238 || protective.FirstLba() != 1 || protective.BlockCount() != 100) { return 2; }

        byte[] header = new byte[512]; byte[] entries = new byte[128];
        header[0] = 69; header[1] = 70; header[2] = 73; header[3] = 32; header[4] = 80; header[5] = 65; header[6] = 82; header[7] = 84;
        Write32(header, 8, 65536); Write32(header, 12, 92); Write64(header, 24, 1); Write64(header, 32, 999);
        Write64(header, 40, 34); Write64(header, 48, 900); Write64(header, 72, 2); Write32(header, 80, 1); Write32(header, 84, 128);
        entries[0] = 40; Write64(entries, 32, 40); Write64(entries, 40, 99);
        Write32(header, 88, PartitionBytes.Crc32(entries, 0, 128, 128, 0));
        Write32(header, 16, PartitionBytes.Crc32(header, 0, 92, 16, 4));
        if (!Gpt.IsValidHeader(header) || !Gpt.ValidateEntries(header, entries, 128)) { return 3; }
        Partition data = Gpt.Entry(header, entries, 128, 0);
        if (!data.Present() || !data.IsGpt() || data.Type() != 40 || data.FirstLba() != 40 || data.BlockCount() != 60) { return 4; }
        entries[0] = 41;
        if (Gpt.ValidateEntries(header, entries, 128) || Gpt.Entry(header, entries, 128, 0).Present()) { return 5; }
        System.Console.WriteLine("Australis GPT and MBR parser tests passed");
        return 0;
    }
}
