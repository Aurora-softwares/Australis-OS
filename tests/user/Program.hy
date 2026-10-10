using Australis.Kernel.Storage;
using Australis.User;

public class UserMockTerminal : IUserTerminal {
    private byte[] input; private int inputCursor; private byte[] output; private int outputLength;
    public UserMockTerminal(byte[] inputBytes) {
        input = inputBytes; inputCursor = 0; output = new byte[4096]; outputLength = 0;
    }
    public int ReadByte() {
        if (inputCursor >= input.Length) { return -1; }
        int value = input[inputCursor]; inputCursor = inputCursor + 1; return value;
    }
    public bool WriteByte(int value) {
        if (value < 0 || value > 255 || outputLength >= output.Length) { return false; }
        output[outputLength] = (byte)value; outputLength = outputLength + 1; return true;
    }
    public bool Contains(byte[] expected) {
        if (expected == null || expected.Length > outputLength) { return false; }
        int start = 0;
        while (start <= outputLength - expected.Length) {
            int i = 0;
            while (i < expected.Length && output[start + i] == expected[i]) { i = i + 1; }
            if (i == expected.Length) { return true; }
            start = start + 1;
        }
        return false;
    }
}

public class UserMockFiles : IUserFiles {
    private bool open; private int position; private bool closeAllCalled;
    public UserMockFiles() { open = false; position = 0; closeAllCalled = false; }
    public int Open(byte[] path, int count) {
        if (path == null || count != 10 || path[0] != 47 || path[1] != 104 ||
            path[2] != 101 || path[3] != 108 || path[4] != 108 || path[5] != 111 ||
            path[6] != 46 || path[7] != 116 || path[8] != 120 || path[9] != 116) { return -1; }
        open = true; position = 0; return 3;
    }
    public int Read(int descriptor, byte[] destination, int capacity) {
        if (!open || descriptor != 3 || destination == null || capacity < 0 ||
            capacity > destination.Length) { return -1; }
        int remaining = 5 - position; int count = capacity;
        if (remaining < count) { count = remaining; }
        int i = 0;
        while (i < count) {
            int index = position + i;
            if (index == 0) { destination[i] = 104; }
            else if (index == 1) { destination[i] = 101; }
            else if (index == 2 || index == 3) { destination[i] = 108; }
            else { destination[i] = 111; }
            i = i + 1;
        }
        position = position + count; return count;
    }
    public bool Close(int descriptor) {
        if (!open || descriptor != 3) { return false; }
        open = false; return true;
    }
    public void CloseAll() { open = false; closeAllCalled = true; }
    public bool CloseAllCalled() { return closeAllCalled; }
}

public class UserBytecodeBuilder {
    private byte[] code; private int length;
    public UserBytecodeBuilder() { code = new byte[256]; length = 0; }
    public void Byte(int value) { code[length] = (byte)value; length = length + 1; }
    public void U32(long value) {
        int i = 0;
        while (i < 4) { Byte((int)(value % 256)); value = value / 256; i = i + 1; }
    }
    public void Write(long address, int count) { Byte(2); U32(address); U32(count); }
    public void ReadTerminal(long address, int count) { Byte(3); U32(address); U32(count); }
    public void WriteCount(long address) { Byte(4); U32(address); }
    public void Open(long address, int count) { Byte(5); U32(address); U32(count); }
    public void ReadFile(long address, int count) { Byte(6); U32(address); U32(count); }
    public void Close() { Byte(7); }
    public void Store(long address, int value) { Byte(8); U32(address); Byte(value); }
    public void Yield() { Byte(9); }
    public void Jump(int target) { Byte(10); U32(target); }
    public void Exit(int value) { Byte(1); Byte(value); }
    public byte[] Bytes() {
        byte[] result = new byte[length]; int i = 0;
        while (i < length) { result[i] = code[i]; i = i + 1; }
        return result;
    }
}

public class UserImages {
    private static void Write32(byte[] bytes, int offset, long value) {
        int i = 0;
        while (i < 4) { bytes[offset + i] = (byte)(value % 256); value = value / 256; i = i + 1; }
    }
    private static byte[] Image(byte[] code, byte[] data, int capacity) {
        byte[] result = new byte[32 + code.Length + data.Length];
        result[0] = 65; result[1] = 85; result[2] = 69; result[3] = 88;
        result[4] = 1; result[5] = 32;
        Write32(result, 8, code.Length); Write32(result, 12, data.Length);
        Write32(result, 16, capacity); Write32(result, 20, 0);
        int i = 0;
        while (i < code.Length) { result[32 + i] = code[i]; i = i + 1; }
        i = 0;
        while (i < data.Length) { result[32 + code.Length + i] = data[i]; i = i + 1; }
        Write32(result, 24, PartitionBytes.Crc32(result, 32, code.Length, code.Length, 0));
        Write32(result, 28, PartitionBytes.Crc32(result, 32 + code.Length, data.Length, data.Length, 0));
        return result;
    }
    public static byte[] Demo() {
        byte[] data = new byte[96];
        data[0] = 117; data[1] = 115; data[2] = 101; data[3] = 114; data[4] = 62; data[5] = 32;
        data[16] = 105; data[17] = 110; data[18] = 112; data[19] = 117;
        data[20] = 116; data[21] = 58; data[22] = 32;
        data[32] = 13; data[33] = 10;
        data[48] = 47; data[49] = 104; data[50] = 101; data[51] = 108; data[52] = 108;
        data[53] = 111; data[54] = 46; data[55] = 116; data[56] = 120; data[57] = 116;
        data[64] = 102; data[65] = 105; data[66] = 108; data[67] = 101; data[68] = 58; data[69] = 32;
        UserBytecodeBuilder code = new UserBytecodeBuilder();
        code.Write(UserAddressSpace.DataBase(), 6);
        code.ReadTerminal(UserAddressSpace.DataBase() + 128, 32);
        code.Write(UserAddressSpace.DataBase() + 16, 7);
        code.WriteCount(UserAddressSpace.DataBase() + 128);
        code.Write(UserAddressSpace.DataBase() + 32, 2);
        code.Open(UserAddressSpace.DataBase() + 48, 10);
        code.ReadFile(UserAddressSpace.DataBase() + 256, 32);
        code.Write(UserAddressSpace.DataBase() + 64, 6);
        code.WriteCount(UserAddressSpace.DataBase() + 256);
        code.Close(); code.Exit(0);
        return Image(code.Bytes(), data, 512);
    }
    public static byte[] Fault() {
        byte[] data = new byte[1]; UserBytecodeBuilder code = new UserBytecodeBuilder();
        code.Store(4096, 65); code.Exit(0); return Image(code.Bytes(), data, 64);
    }
    public static byte[] Loop() {
        byte[] data = new byte[0]; UserBytecodeBuilder code = new UserBytecodeBuilder();
        code.Yield(); code.Jump(0); return Image(code.Bytes(), data, 1);
    }
}

public class Program {
    private static byte[] InputText() {
        byte[] input = new byte[5]; input[0] = 97; input[1] = 98; input[2] = 8;
        input[3] = 99; input[4] = 13; return input;
    }
    private static byte[] ExpectedInput() {
        byte[] value = new byte[9]; value[0] = 105; value[1] = 110; value[2] = 112;
        value[3] = 117; value[4] = 116; value[5] = 58; value[6] = 32;
        value[7] = 97; value[8] = 99; return value;
    }
    private static byte[] ExpectedFile() {
        byte[] value = new byte[11]; value[0] = 102; value[1] = 105; value[2] = 108;
        value[3] = 101; value[4] = 58; value[5] = 32; value[6] = 104;
        value[7] = 101; value[8] = 108; value[9] = 108; value[10] = 111; return value;
    }
    public static int Main() {
        byte[] demo = UserImages.Demo();
        UserExecutable executable = new UserExecutable(demo);
        if (!executable.IsValid() || executable.DataCapacity() != 512) { return 1; }
        UserMockTerminal terminal = new UserMockTerminal(InputText());
        UserProgramResult result = new UserProgramHost(terminal, new UserMockFiles()).Run(executable);
        if (result.State() != UserProgramState.Exited() || result.ExitCode() != 0 ||
            result.Fault() != UserFault.None() || !terminal.Contains(ExpectedInput()) ||
            !terminal.Contains(ExpectedFile())) { return 2; }

        UserExecutable faultExecutable = new UserExecutable(UserImages.Fault());
        UserProcess faultProcess = new UserProcess(faultExecutable,
            new UserSystemCalls(new UserMockTerminal(new byte[0]), new UserMockFiles()));
        result = new UserScheduler().Run(faultProcess);
        if (result.State() != UserProgramState.Faulted() ||
            result.Fault() != UserFault.MemoryAccess() ||
            faultProcess.AddressSpace().WriteByte(UserAddressSpace.CodeBase(), 1) ||
            faultProcess.AddressSpace().WriteByte(4096, 1)) { return 3; }

        byte[] damaged = UserImages.Demo(); damaged[damaged.Length - 1] = 1;
        if (new UserExecutable(damaged).IsValid()) { return 4; }

        UserMockFiles loopFiles = new UserMockFiles();
        result = new UserProgramHost(new UserMockTerminal(new byte[0]), loopFiles).Run(
            new UserExecutable(UserImages.Loop()));
        if (result.State() != UserProgramState.Faulted() ||
            result.Fault() != UserFault.InstructionLimit() || !loopFiles.CloseAllCalled()) { return 5; }

        byte[] command = new byte[20];
        command[0] = 32; command[1] = 32; command[2] = 114; command[3] = 117;
        command[4] = 110; command[5] = 32; command[6] = 32; command[7] = 32;
        command[8] = 47; command[9] = 100; command[10] = 101; command[11] = 109;
        command[12] = 111; command[13] = 46; command[14] = 101; command[15] = 120;
        command[16] = 101; command[17] = 99; command[18] = 32; command[19] = 32;
        UserShellCommand parsed = new UserShellRegistry().Parse(command, command.Length);
        if (parsed.Identifier() != UserShellCommandId.Run() || parsed.ArgumentStart() != 8 ||
            parsed.ArgumentLength() != 10) { return 6; }
        byte[] panicCommand = new byte[10];
        panicCommand[0] = 112; panicCommand[1] = 97; panicCommand[2] = 110;
        panicCommand[3] = 105; panicCommand[4] = 99; panicCommand[5] = 45;
        panicCommand[6] = 116; panicCommand[7] = 101; panicCommand[8] = 115;
        panicCommand[9] = 116;
        parsed = new UserShellRegistry().Parse(panicCommand, panicCommand.Length);
        if (parsed.Identifier() != UserShellCommandId.PanicTest() || parsed.HasArgument()) { return 7; }
        System.Console.WriteLine("Australis user runtime tests passed");
        return 0;
    }
}
