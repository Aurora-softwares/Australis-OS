using Australis.Kernel.Storage;

public class Program {
    public static int Main() {
        if (!Nvme.IsReady(1) || Nvme.IsReady(0) || Nvme.ControllerConfiguration() != 4587520) { return 1; }
        long cap = 1;
        int shifts = 0;
        while (shifts < 32) { cap = cap * 2; shifts = shifts + 1; }
        cap = cap * 4; // DSTRD=4, so stride is 64 bytes
        if (Nvme.DoorbellStride(cap) != 64) { return 2; }
        long high = 2147483647; high = high + 1;
        if (Nvme.DoorbellStrideFromHigh(high) != 4 || Nvme.DoorbellStrideFromHigh(8) != 0) { return 10; }
        long divisor = 65536; divisor = divisor * divisor;
        if (Nvme.DoorbellStride(high * divisor) != 4) { return 11; }

        byte[] command = new byte[64];
        if (!Nvme.BuildIdentify(command, 9, 1, true, 8192) || command[0] != 6 || command[2] != 9 ||
            command[4] != 1 || command[24] != 0 || command[25] != 32 || command[40] != 1) { return 3; }
        if (!Nvme.BuildIdentify(command, 1, 1, false, 12288) || Nvme.BuildIdentify(command, 1, 0, false, 8192)) { return 4; }
        if (!Nvme.BuildRead(command, 15, 3, 12288, 4660, 4, 512) || command[0] != 2 || command[2] != 15 ||
            command[4] != 3 || command[24] != 0 || command[25] != 48 || command[40] != 52 || command[41] != 18 ||
            command[48] != 3) { return 5; }
        if (Nvme.BuildRead(command, 1, 1, 12288, 0, 9, 512) || Nvme.BuildRead(command, 1, 0, 12288, 0, 1, 512)) { return 6; }

        byte[] identify = new byte[4096];
        identify[0] = 0; identify[1] = 0; identify[2] = 16; // 1,048,576 blocks
        identify[26] = 1;
        identify[128 + 4 + 2] = 9;
        if (Nvme.NamespaceSectorSize(identify) != 512 || Nvme.NamespaceSectorCount(identify) != 1048576) { return 7; }
        identify[128 + 4 + 2] = 13;
        if (Nvme.NamespaceSectorSize(identify) != 0 || Nvme.NamespaceSectorCount(identify) != 0) { return 8; }
        identify[128 + 4 + 2] = 9; identify[2] = 0;
        if (Nvme.NamespaceSectorCount(identify) != 0) { return 9; }
        System.Console.WriteLine("Australis NVMe protocol tests passed");
        return 0;
    }
}
