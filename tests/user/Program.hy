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
    private bool created; private bool writeOpen; private byte[] content;
    private int contentLength;
    public UserMockFiles() {
        open = false; position = 0; closeAllCalled = false;
        created = false; writeOpen = false; content = new byte[32]; contentLength = 0;
    }
    private bool NewPath(byte[] path, int count) {
        return path != null && count == 9 && path[0] == 47 && path[1] == 100 &&
            path[2] == 97 && path[3] == 116 && path[4] == 97 &&
            path[5] == 47 && path[6] == 110 && path[7] == 101 && path[8] == 119;
    }
    public int Open(byte[] path, int count) {
        if (path == null || count != 10 || path[0] != 47 || path[1] != 104 ||
            path[2] != 101 || path[3] != 108 || path[4] != 108 || path[5] != 111 ||
            path[6] != 46 || path[7] != 116 || path[8] != 120 || path[9] != 116) { return -1; }
        open = true; position = 0; return 3;
    }
    public int Read(int descriptor, byte[] destination, int capacity) {
        if (!open || descriptor != 3 || destination == null || capacity < 0 ||
            capacity > destination.Length) { return -1; }
        if (capacity == 4 && position == 0) {
            destination[0] = 1; destination[1] = 2;
            destination[2] = 3; destination[3] = 255;
            position = 4; return 4;
        }
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
    public int OpenWrite(byte[] path, int count) {
        if (!created || !NewPath(path, count)) { return -4; }
        writeOpen = true; return 4;
    }
    public int Write(int descriptor, byte[] source, int count, bool append) {
        if (!writeOpen || descriptor != 4 || source == null || count < 0 ||
            count > source.Length) { return 1; }
        int start = 0;
        if (append) { start = contentLength; }
        if (count > content.Length - start) { return 11; }
        int i = 0;
        while (i < count) { content[start + i] = source[i]; i = i + 1; }
        contentLength = start + count; return 0;
    }
    public int Truncate(int descriptor, long length) {
        if (!writeOpen || descriptor != 4 || length < 0 || length > content.Length) {
            return 1;
        }
        int i = contentLength;
        while (i < length) { content[i] = 0; i = i + 1; }
        contentLength = (int)length; return 0;
    }
    public int Create(byte[] path, int count, byte[] contents) {
        if (!NewPath(path, count) || contents == null || contents.Length > content.Length) {
            return 1;
        }
        if (created) { return 9; }
        created = true; contentLength = contents.Length;
        int i = 0;
        while (i < contentLength) { content[i] = contents[i]; i = i + 1; }
        return 0;
    }
    public int Delete(byte[] path, int count) {
        if (!created || !NewPath(path, count)) { return 4; }
        created = false; writeOpen = false; return 0;
    }
    public int Mkdir(byte[] path, int count) { return 8; }
    public int Rmdir(byte[] path, int count) { return 8; }
    public int Rename(byte[] source, int sourceCount, byte[] destination,
        int destinationCount) { return 8; }
    public UserFileInfo Stat(byte[] path, int count) {
        if (count == 10 && path[0] == 47 && path[1] == 104) {
            return new UserFileInfo(0, 1, 5, 17, 0, 0, 0, 0);
        }
        if (count == 1 && path[0] == 47) {
            return new UserFileInfo(0, 2, 0, 1, 0, 0, 0, 0);
        }
        if (created && NewPath(path, count)) {
            return new UserFileInfo(0, 1, contentLength, 18, 0, 0, 0, 0);
        }
        return new UserFileInfo(4, 0, 0, 0, 0, 0, 0, 0);
    }
    public UserDirectoryInfo DirectoryCount(byte[] path, int count) {
        if (count == 1 && path[0] == 47) { return new UserDirectoryInfo(0, 1); }
        return new UserDirectoryInfo(4, 0);
    }
    public int DirectoryName(byte[] path, int count, int index, byte[] destination) {
        if (count == 1 && path[0] == 47 && index == 1) { return -5; }
        if (count != 1 || path[0] != 47 || index != 0 ||
            destination == null || destination.Length < 9) { return -1; }
        destination[0] = 104; destination[1] = 101; destination[2] = 108;
        destination[3] = 108; destination[4] = 111; destination[5] = 46;
        destination[6] = 116; destination[7] = 120; destination[8] = 116;
        return 9;
    }
    public bool Close(int descriptor) {
        if (descriptor == 4 && writeOpen) { writeOpen = false; return true; }
        if (!open || descriptor != 3) { return false; }
        open = false; return true;
    }
    public void CloseAll() {
        open = false; writeOpen = false; closeAllCalled = true;
    }
    public bool CloseAllCalled() { return closeAllCalled; }
    public bool Created() { return created; }
    public int ContentLength() { return contentLength; }
    public int ContentByte(int index) { return content[index]; }
}

public class UserBytecodeBuilder {
    private byte[] code; private int length;
    public UserBytecodeBuilder() { code = new byte[1024]; length = 0; }
    public void Byte(int value) { code[length] = (byte)value; length = length + 1; }
    public void U32(long value) {
        int i = 0;
        while (i < 4) { Byte((int)(value % 256)); value = value / 256; i = i + 1; }
    }
    public int Position() { return length; }
    public void PatchU32(int offset, long value) {
        int i = 0;
        while (i < 4) { code[offset + i] = (byte)(value % 256); value = value / 256; i = i + 1; }
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
    public void Push(int value) { Byte(11); U32(value); }
    public void Load(int slot) { Byte(12); Byte(slot); }
    public void StoreLocal(int slot) { Byte(13); Byte(slot); }
    public void Pop() { Byte(14); }
    public void Add() { Byte(15); }
    public void Divide() { Byte(18); }
    public void Less() { Byte(23); }
    public int JumpIfFalse() { Byte(28); int patch = length; U32(0); return patch; }
    public void ExitValue() { Byte(29); }
    public void WriteValue(int format) { Byte(32); Byte(format); }
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
    public static byte[] OutOfRangeArgument() {
        UserBytecodeBuilder code = new UserBytecodeBuilder();
        code.Push(0); code.Byte(46); code.ExitValue();
        return Image(code.Bytes(), new byte[0], 0);
    }
    public static byte[] BadArgumentTextHandle() {
        UserBytecodeBuilder code = new UserBytecodeBuilder();
        code.Push(4096); code.Byte(48); code.Byte(0); code.Exit(0);
        return Image(code.Bytes(), new byte[0], 0);
    }
    public static byte[] BadDynamicPathHandle() {
        UserBytecodeBuilder code = new UserBytecodeBuilder();
        code.Push(4096); code.Byte(51); code.Byte(0); code.Exit(0);
        return Image(code.Bytes(), new byte[0], 0);
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
    public static byte[] ArithmeticLoop() {
        byte[] data = new byte[0]; UserBytecodeBuilder code = new UserBytecodeBuilder();
        code.Push(0); code.StoreLocal(0); code.Pop();
        code.Push(1); code.StoreLocal(1); code.Pop();
        int condition = code.Position();
        code.Load(1); code.Push(6); code.Less(); int done = code.JumpIfFalse();
        code.Load(0); code.Load(1); code.Add(); code.StoreLocal(0); code.Pop();
        code.Load(1); code.Push(1); code.Add(); code.StoreLocal(1); code.Pop();
        code.Jump(condition); code.PatchU32(done, code.Position());
        code.Load(0); code.WriteValue(1); code.Load(0); code.ExitValue();
        return Image(code.Bytes(), data, 1);
    }
    public static byte[] DivideByZero() {
        byte[] data = new byte[0]; UserBytecodeBuilder code = new UserBytecodeBuilder();
        code.Push(9); code.Push(0); code.Divide(); code.ExitValue();
        return Image(code.Bytes(), data, 1);
    }
    public static byte[] Api() {
        long baseAddress = UserAddressSpace.DataBase();
        byte[] data = new byte[64];
        byte[] hello = new byte[10];
        hello[0] = 47; hello[1] = 104; hello[2] = 101; hello[3] = 108;
        hello[4] = 108; hello[5] = 111; hello[6] = 46; hello[7] = 116;
        hello[8] = 120; hello[9] = 116;
        int i = 0;
        while (i < 10) { data[i] = hello[i]; i = i + 1; }
        data[16] = 47;
        byte[] next = new byte[9];
        next[0] = 47; next[1] = 100; next[2] = 97; next[3] = 116;
        next[4] = 97; next[5] = 47; next[6] = 110; next[7] = 101;
        next[8] = 119;
        i = 0; while (i < 9) { data[32 + i] = next[i]; i = i + 1; }
        data[48] = 97; data[49] = 98; data[50] = 99; data[51] = 100;
        UserBytecodeBuilder code = new UserBytecodeBuilder();
        code.Byte(33); code.Byte(0); code.U32(baseAddress); code.U32(10);
        code.WriteValue(1);
        code.Byte(33); code.Byte(1); code.U32(baseAddress); code.U32(10);
        code.WriteValue(1);
        code.Byte(34); code.U32(baseAddress + 16); code.U32(1);
        code.WriteValue(1);
        code.Push(0); code.Byte(35); code.U32(baseAddress + 16);
        code.U32(1); code.U32(baseAddress + 128); code.Pop();
        code.WriteCount(baseAddress + 128);
        code.Byte(11); code.U32(4294967295);
        code.Byte(35); code.U32(baseAddress + 16);
        code.U32(1); code.U32(baseAddress + 128); code.Pop();
        code.Byte(36); code.U32(baseAddress + 32); code.U32(9);
        code.U32(baseAddress + 48); code.U32(3); code.StoreLocal(0); code.Pop();
        code.Byte(37); code.Byte(1); code.U32(baseAddress + 32);
        code.U32(9); code.StoreLocal(1); code.Pop();
        code.Byte(38); code.Byte(1); code.U32(baseAddress + 51);
        code.U32(1); code.StoreLocal(2); code.Pop();
        code.Push(2); code.Byte(39); code.StoreLocal(3); code.Pop();
        code.Byte(43); code.StoreLocal(4); code.Pop();
        code.Byte(33); code.Byte(1); code.U32(baseAddress + 32);
        code.U32(9); code.WriteValue(1);
        code.Byte(40); code.Byte(0); code.U32(baseAddress + 32);
        code.U32(9); code.StoreLocal(5); code.Pop();
        code.Byte(42); code.StoreLocal(6); code.Pop();
        code.Load(0); code.Load(1); code.Add(); code.Load(2); code.Add();
        code.Load(3); code.Add(); code.Load(4); code.Add();
        code.Load(5); code.Add(); code.Load(6); code.Add();
        code.ExitValue();
        return Image(code.Bytes(), data, 256);
    }
    public static byte[] BadApiPointer() {
        byte[] data = new byte[1];
        UserBytecodeBuilder code = new UserBytecodeBuilder();
        code.Byte(36); code.U32(4096); code.U32(4);
        code.U32(UserAddressSpace.DataBase()); code.U32(0);
        code.ExitValue();
        return Image(code.Bytes(), data, 64);
    }
}

public class Program {
    private static int CompiledInspector(string imagePath) {
        UserExecutable executable = new UserExecutable(
            System.IO.File.ReadAllBytes(imagePath));
        if (!executable.IsValid()) { return 20; }
        UserMockTerminal terminal = new UserMockTerminal(new byte[0]);
        UserProgramResult result = new UserProgramHost(terminal,
            new UserMockFiles()).Run(executable);
        byte[] expected = new byte[12];
        expected[0] = 47; expected[1] = 104; expected[2] = 101;
        expected[3] = 108; expected[4] = 108; expected[5] = 111;
        expected[6] = 46; expected[7] = 116; expected[8] = 120;
        expected[9] = 116; expected[10] = 13; expected[11] = 10;
        if (result.State() != UserProgramState.Exited() || result.ExitCode() != 0 ||
            !terminal.Contains(expected)) { return 21; }
        System.Console.WriteLine("Compiled Inspector AUEX test passed");
        return 0;
    }
    private static int CompiledFileApi(string imagePath) {
        UserExecutable executable = new UserExecutable(
            System.IO.File.ReadAllBytes(imagePath));
        if (!executable.IsValid()) { return 22; }
        UserMockFiles files = new UserMockFiles();
        UserProgramResult result = new UserProgramHost(
            new UserMockTerminal(new byte[0]), files).Run(executable);
        if (result.State() != UserProgramState.Exited() || result.ExitCode() != 0 ||
            files.Created() || files.ContentLength() != 2 ||
            files.ContentByte(0) != 120 || files.ContentByte(1) != 121) {
            return 23;
        }
        System.Console.WriteLine("Compiled file API AUEX test passed");
        return 0;
    }
    private static int CompiledPortableApi(string imagePath) {
        UserExecutable executable = new UserExecutable(
            System.IO.File.ReadAllBytes(imagePath));
        if (!executable.IsValid() || executable.DataCapacity() != 65536) { return 29; }
        UserMockTerminal terminal = new UserMockTerminal(InputText());
        UserProgramResult result = new UserProgramHost(terminal,
            new UserMockFiles()).Run(executable);
        if (result.State() != UserProgramState.Exited() || result.ExitCode() != 0 ||
            result.Fault() != UserFault.None() || !terminal.Contains(ExpectedInput()) ||
            !terminal.Contains(ExpectedFile())) { return 30; }
        System.Console.WriteLine("Compiled portable AUEX API test passed");
        return 0;
    }
    private static int CompiledPortableIo(string imagePath) {
        UserExecutable executable = new UserExecutable(
            System.IO.File.ReadAllBytes(imagePath));
        if (!executable.IsValid()) { return 31; }
        UserMockFiles files = new UserMockFiles();
        UserProgramResult result = new UserProgramHost(
            new UserMockTerminal(new byte[0]), files).Run(executable);
        if (result.State() != UserProgramState.Exited() || result.ExitCode() != 0 ||
            result.Fault() != UserFault.None() || !files.Created() ||
            files.ContentLength() != 2 || files.ContentByte(0) != 120 ||
            files.ContentByte(1) != 121) { return 32; }
        System.Console.WriteLine("Compiled portable AUEX I/O test passed");
        return 0;
    }
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
    public static int Main(string[] args) {
        if (args != null && args.Length == 2) {
            if (args[0] == "inspector") { return CompiledInspector(args[1]); }
            if (args[0] == "file-api") { return CompiledFileApi(args[1]); }
            if (args[0] == "portable-api") { return CompiledPortableApi(args[1]); }
            if (args[0] == "portable-io") { return CompiledPortableIo(args[1]); }
            return 24;
        }
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

        UserMockTerminal arithmeticTerminal = new UserMockTerminal(new byte[0]);
        result = new UserProgramHost(arithmeticTerminal, new UserMockFiles()).Run(
            new UserExecutable(UserImages.ArithmeticLoop()));
        byte[] arithmeticOutput = new byte[4]; arithmeticOutput[0] = 49; arithmeticOutput[1] = 53;
        arithmeticOutput[2] = 13; arithmeticOutput[3] = 10;
        if (result.State() != UserProgramState.Exited() || result.ExitCode() != 15 ||
            result.Fault() != UserFault.None() || !arithmeticTerminal.Contains(arithmeticOutput)) { return 8; }

        result = new UserProgramHost(new UserMockTerminal(new byte[0]), new UserMockFiles()).Run(
            new UserExecutable(UserImages.DivideByZero()));
        if (result.State() != UserProgramState.Faulted() || result.Fault() != UserFault.Arithmetic()) { return 9; }

        UserMockTerminal apiTerminal = new UserMockTerminal(new byte[0]);
        UserMockFiles apiFiles = new UserMockFiles();
        result = new UserProgramHost(apiTerminal, apiFiles).Run(
            new UserExecutable(UserImages.Api()));
        byte[] directoryName = new byte[9];
        directoryName[0] = 104; directoryName[1] = 101; directoryName[2] = 108;
        directoryName[3] = 108; directoryName[4] = 111; directoryName[5] = 46;
        directoryName[6] = 116; directoryName[7] = 120; directoryName[8] = 116;
        if (result.State() != UserProgramState.Exited() || result.ExitCode() != 0 ||
            !apiTerminal.Contains(directoryName) || apiFiles.Created() ||
            apiFiles.ContentLength() != 2 || apiFiles.ContentByte(0) != 97 ||
            apiFiles.ContentByte(1) != 98) { return 10; }

        result = new UserProgramHost(new UserMockTerminal(new byte[0]),
            new UserMockFiles()).Run(new UserExecutable(UserImages.BadApiPointer()));
        if (result.State() != UserProgramState.Exited() || result.ExitCode() != 1) {
            return 11;
        }

        result = new UserProgramHost(new UserMockTerminal(new byte[0]),
            new UserMockFiles()).Run(new UserExecutable(UserImages.OutOfRangeArgument()));
        if (result.State() != UserProgramState.Faulted() ||
            result.Fault() != UserFault.MemoryAccess()) { return 25; }
        result = new UserProgramHost(new UserMockTerminal(new byte[0]),
            new UserMockFiles()).Run(new UserExecutable(UserImages.BadArgumentTextHandle()));
        if (result.State() != UserProgramState.Faulted() ||
            result.Fault() != UserFault.MemoryAccess()) { return 27; }
        result = new UserProgramHost(new UserMockTerminal(new byte[0]),
            new UserMockFiles()).Run(new UserExecutable(UserImages.BadDynamicPathHandle()));
        if (result.State() != UserProgramState.Faulted() ||
            result.Fault() != UserFault.MemoryAccess()) { return 28; }
        int[] badStarts = new int[1]; badStarts[0] = 1;
        int[] badSizes = new int[1]; badSizes[0] = 1;
        UserArguments badArguments = new UserArguments(new byte[1],
            badStarts, badSizes, 1);
        if (badArguments.IsValid()) { return 26; }
        byte[] startText = new byte[6];
        startText[0] = 97; startText[1] = 98; startText[2] = 99;
        startText[3] = 88; startText[4] = 61; startText[5] = 49;
        int[] starts = new int[1]; starts[0] = 0;
        int[] lengths = new int[1]; lengths[0] = 3;
        UserArguments startArguments = new UserArguments(startText, starts, lengths, 1);
        int[] envStarts = new int[1]; envStarts[0] = 3;
        UserArguments startEnvironment = new UserArguments(startText, envStarts, lengths, 1);
        byte[] directory = new byte[5];
        directory[0] = 47; directory[1] = 100; directory[2] = 97;
        directory[3] = 116; directory[4] = 97;
        UserProcessStart processStart = new UserProcessStart(startArguments,
            startEnvironment, directory, 0, 1, 2);
        UserAddressSpace startMemory = new UserAddressSpace(executable);
        UserArguments copied = processStart.CopyTo(startMemory);
        long recordBase = UserAddressSpace.StartBase();
        if (!processStart.IsValid() || copied == null || !copied.IsValid() ||
            copied.ByteAt(0, 0) != 97 || copied.ByteAt(0, 2) != 99 ||
            startMemory.ReadByte(recordBase) != 65 ||
            startMemory.ReadByte(recordBase + 4) != UserProcessStart.Version() ||
            startMemory.ReadByte(recordBase + 12) != 1 ||
            startMemory.ReadByte(recordBase + 16) != 1 ||
            startMemory.WriteByte(recordBase, 0)) { return 33; }
        startText[0] = 122;
        if (copied.ByteAt(0, 0) != 97 ||
            new UserProcessStart(startArguments, startEnvironment,
                directory, 0, 0, 2).IsValid()) { return 34; }
        int[] overlappingStarts = new int[2]; overlappingStarts[1] = 1;
        int[] overlappingLengths = new int[2];
        overlappingLengths[0] = 3; overlappingLengths[1] = 3;
        if (new UserArguments(startText, overlappingStarts,
            overlappingLengths, 2).IsValid()) { return 35; }
        UserMockFiles processFiles = new UserMockFiles();
        UserProgramHost processHost = new UserProgramHost(
            new UserMockTerminal(new byte[0]), processFiles);
        UserExecutable arithmeticImage = new UserExecutable(UserImages.ArithmeticLoop());
        int firstPid = processHost.SpawnForeground(arithmeticImage,
            new UserProcessStart(new UserArguments(new byte[0],
                new int[0], new int[0], 0)));
        if (firstPid != 1 || processHost.SpawnForeground(arithmeticImage,
                new UserProcessStart(startArguments)) != -1 ||
            processHost.Wait(2).Pid() != 0) { return 36; }
        UserProgramResult waited = processHost.Wait(firstPid);
        if (waited.Pid() != 1 || waited.State() != UserProgramState.Exited() ||
            waited.ExitCode() != 15 || !processFiles.CloseAllCalled()) { return 37; }
        int secondPid = processHost.SpawnForeground(arithmeticImage,
            new UserProcessStart(startArguments));
        waited = processHost.Wait(secondPid);
        if (secondPid != 2 || waited.Pid() != 2 || waited.ExitCode() != 15) { return 38; }
        UserSystemCalls checkedCalls = new UserSystemCalls(
            new UserMockTerminal(new byte[0]), new UserMockFiles(), 7);
        UserSyscallResult information = checkedCalls.SystemInformation(3);
        UserSyscallResult invalidInformation = checkedCalls.SystemInformation(99);
        UserSyscallResult opened = checkedCalls.OpenResult(startMemory,
            UserAddressSpace.DataBase() + 48, 10, false);
        if (information.Status() != UserSyscallStatus.Success() ||
            information.Value() != 7 ||
            invalidInformation.Status() != UserSyscallStatus.InvalidArgument() ||
            opened.Status() != UserSyscallStatus.Success() || opened.Value() != 3) {
            return 39;
        }
        UserSyscallResult read = checkedCalls.ReadResult(3, startMemory,
            UserAddressSpace.DataBase() + 256, 4);
        if (read.Status() != UserSyscallStatus.Success() || read.Value() != 4 ||
            checkedCalls.ReadResult(3, startMemory,
                UserAddressSpace.DataBase() + 256, 4).Value() != 1 ||
            checkedCalls.ReadResult(3, startMemory,
                UserAddressSpace.DataBase() + 256, 4).Status() !=
                UserSyscallStatus.EndOfFile()) { return 40; }
        checkedCalls.CloseAll();

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
