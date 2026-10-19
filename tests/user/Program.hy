using Australis.Kernel.Storage;
using Australis.User;

public class UserMockTerminal : IUserTerminal {
    private byte[] input; private int inputCursor; private byte[] output; private int outputLength;
    private int delayedReads;
    public UserMockTerminal(byte[] inputBytes) {
        input = inputBytes; inputCursor = 0; output = new byte[4096]; outputLength = 0;
        delayedReads = 0;
    }
    public UserMockTerminal(byte[] inputBytes, int delay) {
        input = inputBytes; inputCursor = 0; output = new byte[4096]; outputLength = 0;
        delayedReads = delay;
    }
    public int ReadByte() {
        if (delayedReads > 0) { delayedReads = delayedReads - 1; return -3; }
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

public class UserMockChildLauncher : IUserChildLauncher {
    private int launches;
    public UserMockChildLauncher() { launches = 0; }
    public int Launches() { return launches; }
    public int RunChild(byte[] path, UserArguments arguments) {
        if (path == null || path.Length != 30 || path[0] != 47 ||
            path[1] != 83 || path[7] != 47 || path[12] != 47 ||
            path[29] != 99 || arguments == null || arguments.Count() != 0) {
            return -1;
        }
        launches = launches + 1;
        return 0;
    }
    public int RunChildWithContext(int parentPid, byte[] path, UserArguments arguments,
        UserArguments environment, byte[] workingDirectory) {
        return RunChild(path, arguments);
    }
    public int SpawnChildWithContext(int parentPid, byte[] path,
        UserArguments arguments, UserArguments environment,
        byte[] workingDirectory) {
        if (path == null || path.Length < 20 || path[0] != 47 ||
            arguments == null || arguments.Count() != 0) { return -4; }
        launches = launches + 1;
        return launches + 1;
    }
    public int WaitChild(int parentPid, int childPid) { return 0; }
    public int WaitReadyChild(int parentPid, int childPid, int maxRounds) { return 0; }
    public int TerminateChild(int parentPid, int childPid) { return -4; }
    public int SleepProcess(int processId, int milliseconds) { return -4; }
    public int ChannelOpen(int processId, int childPid, int version) { return -4; }
    public int ChannelAccept(int processId, int version) { return -4; }
    public int ChannelSend(int processId, int handle, int version,
        byte[] source, int length) { return -4; }
    public int ChannelReceive(int processId, int handle, byte[] destination) { return -4; }
    public int ChannelWait(int processId, int handle, int maxRounds) { return -4; }
    public int ChannelPeer(int processId, int handle) { return -4; }
    public int ChannelClose(int processId, int handle) { return -4; }
    public int DisplayClaim(int processId) { return -4; }
    public int DisplayRelease(int processId) { return -4; }
    public int DisplayFillRect(int processId, int x, int y, int width,
        int height, int rgb) { return -4; }
    public int DisplaySetMode(int processId, int width, int height) { return -4; }
    public int DisplayPollMouse(int processId, byte[] destination) { return -4; }
    public int DisplayCaptureKeyboard(int processId, int enabled) { return -4; }
    public int DisplayPollKey(int processId) { return -4; }
    public long ClockNow() { return 0; }
    public long ClockDeadlineAfter(int milliseconds) { return 0; }
    public int MarkReady(int processId) { return 0; }
    public int RunNativeRound() { return 0; }
    public void ProcessExited(UserProgramResult result) { }
    public void BeforeTerminalInput(int processId) { }
    public void AfterTerminalInput(int processId) { }
}

public class UserMockFailingChildLauncher : IUserChildLauncher {
    private int launches;
    public UserMockFailingChildLauncher() { launches = 0; }
    public int Launches() { return launches; }
    public int RunChild(byte[] path, UserArguments arguments) {
        launches = launches + 1; return -100;
    }
    public int RunChildWithContext(int parentPid, byte[] path, UserArguments arguments,
        UserArguments environment, byte[] workingDirectory) {
        return RunChild(path, arguments);
    }
    public int SpawnChildWithContext(int parentPid, byte[] path,
        UserArguments arguments, UserArguments environment,
        byte[] workingDirectory) {
        launches = launches + 1; return launches + 1;
    }
    public int WaitChild(int parentPid, int childPid) {
        if (childPid <= 3) { return 0; }
        return -100;
    }
    public int WaitReadyChild(int parentPid, int childPid, int maxRounds) {
        if (childPid <= 3) { return 0; }
        return -1;
    }
    public int TerminateChild(int parentPid, int childPid) { return -4; }
    public int SleepProcess(int processId, int milliseconds) { return -4; }
    public int ChannelOpen(int processId, int childPid, int version) { return -4; }
    public int ChannelAccept(int processId, int version) { return -4; }
    public int ChannelSend(int processId, int handle, int version,
        byte[] source, int length) { return -4; }
    public int ChannelReceive(int processId, int handle, byte[] destination) { return -4; }
    public int ChannelWait(int processId, int handle, int maxRounds) { return -4; }
    public int ChannelPeer(int processId, int handle) { return -4; }
    public int ChannelClose(int processId, int handle) { return -4; }
    public int DisplayClaim(int processId) { return -4; }
    public int DisplayRelease(int processId) { return -4; }
    public int DisplayFillRect(int processId, int x, int y, int width,
        int height, int rgb) { return -4; }
    public int DisplaySetMode(int processId, int width, int height) { return -4; }
    public int DisplayPollMouse(int processId, byte[] destination) { return -4; }
    public int DisplayCaptureKeyboard(int processId, int enabled) { return -4; }
    public int DisplayPollKey(int processId) { return -4; }
    public long ClockNow() { return 0; }
    public long ClockDeadlineAfter(int milliseconds) { return 0; }
    public int MarkReady(int processId) { return 0; }
    public int RunNativeRound() { return 0; }
    public void ProcessExited(UserProgramResult result) { }
    public void BeforeTerminalInput(int processId) { }
    public void AfterTerminalInput(int processId) { }
}

public class UserMockCommandLauncher : IUserChildLauncher {
    private int launches;
    public UserMockCommandLauncher() { launches = 0; }
    public int Launches() { return launches; }
    public int RunChild(byte[] path, UserArguments arguments) {
        if (path == null || path.Length != 20 || path[0] != 47 ||
            path[1] != 83 || path[8] != 66 || path[12] != 99 ||
            path[19] != 99 || arguments == null || arguments.Count() != 1 ||
            arguments.Length(0) != 10 || arguments.ByteAt(0, 0) != 47 ||
            arguments.ByteAt(0, 1) != 104 || arguments.ByteAt(0, 9) != 116) {
            return -1;
        }
        launches = launches + 1;
        return 0;
    }
    public int RunChildWithContext(int parentPid, byte[] path, UserArguments arguments,
        UserArguments environment, byte[] workingDirectory) {
        return RunChild(path, arguments);
    }
    public int SpawnChildWithContext(int parentPid, byte[] path,
        UserArguments arguments, UserArguments environment,
        byte[] workingDirectory) { return -4; }
    public int WaitChild(int parentPid, int childPid) { return -4; }
    public int WaitReadyChild(int parentPid, int childPid, int maxRounds) { return -4; }
    public int TerminateChild(int parentPid, int childPid) { return -4; }
    public int SleepProcess(int processId, int milliseconds) { return -4; }
    public int ChannelOpen(int processId, int childPid, int version) { return -4; }
    public int ChannelAccept(int processId, int version) { return -4; }
    public int ChannelSend(int processId, int handle, int version,
        byte[] source, int length) { return -4; }
    public int ChannelReceive(int processId, int handle, byte[] destination) { return -4; }
    public int ChannelWait(int processId, int handle, int maxRounds) { return -4; }
    public int ChannelPeer(int processId, int handle) { return -4; }
    public int ChannelClose(int processId, int handle) { return -4; }
    public int DisplayClaim(int processId) { return -4; }
    public int DisplayRelease(int processId) { return -4; }
    public int DisplayFillRect(int processId, int x, int y, int width,
        int height, int rgb) { return -4; }
    public int DisplaySetMode(int processId, int width, int height) { return -4; }
    public int DisplayPollMouse(int processId, byte[] destination) { return -4; }
    public int DisplayCaptureKeyboard(int processId, int enabled) { return -4; }
    public int DisplayPollKey(int processId) { return -4; }
    public long ClockNow() { return 0; }
    public long ClockDeadlineAfter(int milliseconds) { return 0; }
    public int MarkReady(int processId) { return 0; }
    public int RunNativeRound() { return 0; }
    public void ProcessExited(UserProgramResult result) { }
    public void BeforeTerminalInput(int processId) { }
    public void AfterTerminalInput(int processId) { }
}

public class UserMockFiles : IUserFiles {
    private bool open; private int position; private bool closeAllCalled;
    private bool manifestOpen;
    private bool created; private bool writeOpen; private byte[] content;
    private int contentLength;
    public UserMockFiles() {
        open = false; position = 0; closeAllCalled = false; manifestOpen = false;
        created = false; writeOpen = false; content = new byte[32]; contentLength = 0;
    }
    private bool NewPath(byte[] path, int count) {
        return path != null && count == 9 && path[0] == 47 && path[1] == 100 &&
            path[2] == 97 && path[3] == 116 && path[4] == 97 &&
            path[5] == 47 && path[6] == 110 && path[7] == 101 && path[8] == 119;
    }
    private byte[] MockManifest() {
        byte[] manifest = new byte[143];
        manifest[0] = 65;
        manifest[1] = 85;
        manifest[2] = 83;
        manifest[3] = 77;
        manifest[4] = 49;
        manifest[5] = 10;
        manifest[6] = 68;
        manifest[7] = 101;
        manifest[8] = 118;
        manifest[9] = 105;
        manifest[10] = 99;
        manifest[11] = 101;
        manifest[12] = 124;
        manifest[13] = 47;
        manifest[14] = 83;
        manifest[15] = 121;
        manifest[16] = 115;
        manifest[17] = 116;
        manifest[18] = 101;
        manifest[19] = 109;
        manifest[20] = 47;
        manifest[21] = 67;
        manifest[22] = 111;
        manifest[23] = 114;
        manifest[24] = 101;
        manifest[25] = 47;
        manifest[26] = 68;
        manifest[27] = 101;
        manifest[28] = 118;
        manifest[29] = 105;
        manifest[30] = 99;
        manifest[31] = 101;
        manifest[32] = 46;
        manifest[33] = 101;
        manifest[34] = 120;
        manifest[35] = 101;
        manifest[36] = 99;
        manifest[37] = 124;
        manifest[38] = 50;
        manifest[39] = 124;
        manifest[40] = 53;
        manifest[41] = 48;
        manifest[42] = 48;
        manifest[43] = 48;
        manifest[44] = 124;
        manifest[45] = 79;
        manifest[46] = 10;
        manifest[47] = 83;
        manifest[48] = 116;
        manifest[49] = 111;
        manifest[50] = 114;
        manifest[51] = 97;
        manifest[52] = 103;
        manifest[53] = 101;
        manifest[54] = 124;
        manifest[55] = 47;
        manifest[56] = 83;
        manifest[57] = 121;
        manifest[58] = 115;
        manifest[59] = 116;
        manifest[60] = 101;
        manifest[61] = 109;
        manifest[62] = 47;
        manifest[63] = 67;
        manifest[64] = 111;
        manifest[65] = 114;
        manifest[66] = 101;
        manifest[67] = 47;
        manifest[68] = 83;
        manifest[69] = 116;
        manifest[70] = 111;
        manifest[71] = 114;
        manifest[72] = 97;
        manifest[73] = 103;
        manifest[74] = 101;
        manifest[75] = 46;
        manifest[76] = 101;
        manifest[77] = 120;
        manifest[78] = 101;
        manifest[79] = 99;
        manifest[80] = 124;
        manifest[81] = 50;
        manifest[82] = 124;
        manifest[83] = 53;
        manifest[84] = 48;
        manifest[85] = 48;
        manifest[86] = 48;
        manifest[87] = 124;
        manifest[88] = 79;
        manifest[89] = 10;
        manifest[90] = 67;
        manifest[91] = 111;
        manifest[92] = 109;
        manifest[93] = 109;
        manifest[94] = 97;
        manifest[95] = 110;
        manifest[96] = 100;
        manifest[97] = 83;
        manifest[98] = 104;
        manifest[99] = 101;
        manifest[100] = 108;
        manifest[101] = 108;
        manifest[102] = 124;
        manifest[103] = 47;
        manifest[104] = 83;
        manifest[105] = 121;
        manifest[106] = 115;
        manifest[107] = 116;
        manifest[108] = 101;
        manifest[109] = 109;
        manifest[110] = 47;
        manifest[111] = 67;
        manifest[112] = 111;
        manifest[113] = 114;
        manifest[114] = 101;
        manifest[115] = 47;
        manifest[116] = 67;
        manifest[117] = 111;
        manifest[118] = 109;
        manifest[119] = 109;
        manifest[120] = 97;
        manifest[121] = 110;
        manifest[122] = 100;
        manifest[123] = 83;
        manifest[124] = 104;
        manifest[125] = 101;
        manifest[126] = 108;
        manifest[127] = 108;
        manifest[128] = 46;
        manifest[129] = 101;
        manifest[130] = 120;
        manifest[131] = 101;
        manifest[132] = 99;
        manifest[133] = 124;
        manifest[134] = 51;
        manifest[135] = 124;
        manifest[136] = 53;
        manifest[137] = 48;
        manifest[138] = 48;
        manifest[139] = 48;
        manifest[140] = 124;
        manifest[141] = 83;
        manifest[142] = 10;
        return manifest;
    }
    public int Open(byte[] path, int count) {
        if (path != null && count == 31 && path[0] == 47 &&
            path[1] == 83 && path[8] == 67 && path[15] == 115 &&
            path[30] == 116) {
            open = true; manifestOpen = true; position = 0; return 3;
        }
        if (path == null || count != 10 || path[0] != 47 || path[1] != 104 ||
            path[2] != 101 || path[3] != 108 || path[4] != 108 || path[5] != 111 ||
            path[6] != 46 || path[7] != 116 || path[8] != 120 || path[9] != 116) { return -1; }
        open = true; manifestOpen = false; position = 0; return 3;
    }
    public int Read(int descriptor, byte[] destination, int capacity) {
        if (!open || descriptor != 3 || destination == null || capacity < 0 ||
            capacity > destination.Length) { return -1; }
        if (manifestOpen) {
            byte[] manifest = MockManifest();
            int count = manifest.Length - position;
            if (count > capacity) { count = capacity; }
            int index = 0;
            while (index < count) {
                destination[index] = manifest[position + index];
                index = index + 1;
            }
            position = position + count; return count;
        }
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
        if (count == 20 && path[0] == 47 && path[1] == 83 &&
            path[7] == 47 && path[8] == 66 && path[11] == 47 &&
            path[12] == 99) {
            return new UserFileInfo(0, 1, 1, 19, 0, 0, 0, 0);
        }
        if (count == 11 && path[0] == 47 && path[1] == 83 &&
            path[7] == 47 && path[8] == 66) {
            return new UserFileInfo(0, 2, 0, 20, 0, 0, 0, 0);
        }
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
        open = false; manifestOpen = false; return true;
    }
    public void CloseAll() {
        open = false; manifestOpen = false; writeOpen = false; closeAllCalled = true;
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
    private static int CompiledSystemLaunch(string imagePath) {
        UserExecutable executable = new UserExecutable(
            System.IO.File.ReadAllBytes(imagePath));
        if (!executable.IsValid()) { return 48; }
        UserMockChildLauncher launcher = new UserMockChildLauncher();
        UserProgramResult result = new UserProgramHost(
            new UserMockTerminal(new byte[0]), new UserMockFiles(),
            new int[55], launcher, 1).Run(executable);
        if (result.Pid() != 1 || result.State() != UserProgramState.Exited() ||
            result.ExitCode() != 0 || result.Fault() != UserFault.None() ||
            launcher.Launches() != 3) { return 49; }
        System.Console.WriteLine("Compiled PID 1 launcher passed");
        return 0;
    }
    private static int CompiledSystemFailure(string imagePath) {
        UserExecutable executable = new UserExecutable(
            System.IO.File.ReadAllBytes(imagePath));
        if (!executable.IsValid()) { return 54; }
        UserMockFailingChildLauncher launcher = new UserMockFailingChildLauncher();
        UserProgramResult result = new UserProgramHost(
            new UserMockTerminal(new byte[0]), new UserMockFiles(),
            new int[55], launcher, 1).Run(executable);
        if (result.Pid() != 1 || result.State() != UserProgramState.Exited() ||
            result.ExitCode() != 1 || launcher.Launches() != 5) { return 55; }
        System.Console.WriteLine("PID 1 bounded restart passed");
        return 0;
    }
    private static int CompiledShellPreview(string imagePath) {
        UserExecutable executable = new UserExecutable(
            System.IO.File.ReadAllBytes(imagePath));
        if (!executable.IsValid()) { return 46; }
        byte[] input = new byte[10];
        input[0] = 104; input[1] = 101; input[2] = 108; input[3] = 112;
        input[4] = 13; input[5] = 101; input[6] = 120; input[7] = 105;
        input[8] = 116; input[9] = 13;
        UserMockTerminal terminal = new UserMockTerminal(input, 40);
        UserProgramResult result = new UserProgramHost(terminal,
            new UserMockFiles()).Run(executable);
        byte[] expected = new byte[10];
        expected[0] = 66; expected[1] = 117; expected[2] = 105;
        expected[3] = 108; expected[4] = 116; expected[5] = 45;
        expected[6] = 105; expected[7] = 110; expected[8] = 115;
        expected[9] = 58;
        if (result.State() != UserProgramState.Exited() || result.ExitCode() != 0 ||
            result.Fault() != UserFault.None() || !terminal.Contains(expected)) {
            return 47;
        }
        System.Console.WriteLine("Compiled shell preview passed");
        return 0;
    }
    private static int CompiledShellCommands(string imagePath) {
        UserExecutable executable = new UserExecutable(
            System.IO.File.ReadAllBytes(imagePath));
        if (!executable.IsValid()) { return 50; }
        byte[] input = new byte[25];
        input[0] = 99; input[1] = 97; input[2] = 116; input[3] = 32;
        input[4] = 47; input[5] = 104; input[6] = 101; input[7] = 108;
        input[8] = 108; input[9] = 111; input[10] = 46; input[11] = 116;
        input[12] = 120; input[13] = 116; input[14] = 13;
        input[15] = 112; input[16] = 119; input[17] = 100; input[18] = 13;
        input[19] = 101; input[20] = 120; input[21] = 105;
        input[22] = 116; input[23] = 13;
        UserMockTerminal terminal = new UserMockTerminal(input);
        UserMockCommandLauncher launcher = new UserMockCommandLauncher();
        UserProgramResult result = new UserProgramHost(terminal,
            new UserMockFiles(), new int[55], launcher, 1).Run(executable);
        byte[] expected = new byte[3];
        expected[0] = 47; expected[1] = 13; expected[2] = 10;
        if (result.State() != UserProgramState.Exited() || result.ExitCode() != 0 ||
            result.Fault() != UserFault.None() || launcher.Launches() != 1 ||
            !terminal.Contains(expected)) {
            System.Console.WriteLine("shell state=" + result.State() +
                " exit=" + result.ExitCode() + " fault=" + result.Fault() +
                " launches=" + launcher.Launches());
            return 51;
        }
        System.Console.WriteLine("Compiled shell command launch passed");
        return 0;
    }
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
    private static int CompiledStage1(string imagePath) {
        UserExecutable executable = new UserExecutable(
            System.IO.File.ReadAllBytes(imagePath));
        if (!executable.IsValid()) { return 42; }
        byte[] text = new byte[22];
        byte[] expected = new byte[11];
        expected[0] = 115; expected[1] = 116; expected[2] = 97;
        expected[3] = 103; expected[4] = 101; expected[5] = 49;
        expected[6] = 45; expected[7] = 111; expected[8] = 107;
        expected[9] = 13; expected[10] = 10;
        text[0] = 47; text[1] = 104; text[2] = 101; text[3] = 108;
        text[4] = 108; text[5] = 111; text[6] = 46; text[7] = 116;
        text[8] = 120; text[9] = 116; text[10] = 45; text[11] = 97;
        text[12] = 110; text[13] = 116; text[14] = 119; text[15] = 111;
        text[16] = 32; text[17] = 119; text[18] = 111; text[19] = 114;
        text[20] = 100; text[21] = 115;
        int[] starts = new int[3]; starts[1] = 10; starts[2] = 13;
        int[] lengths = new int[3];
        lengths[0] = 10; lengths[1] = 3; lengths[2] = 9;
        UserArguments arguments = new UserArguments(text, starts, lengths, 3);
        UserMockTerminal terminal = new UserMockTerminal(new byte[0]);
        UserMockFiles files = new UserMockFiles();
        UserProgramHost host = new UserProgramHost(terminal, files);
        int run = 1;
        while (run <= 3) {
            UserProgramResult result = host.Run(executable, arguments);
            if (result.Pid() != run || result.State() != UserProgramState.Exited() ||
                result.ExitCode() != 23 || result.Fault() != UserFault.None() ||
                !terminal.Contains(expected) || !files.CloseAllCalled()) { return 43; }
            run = run + 1;
        }
        System.Console.WriteLine("Compiled stage 1 AUEX test passed");
        return 0;
    }
    private static int CompiledStage1Starter(string imagePath) {
        UserExecutable executable = new UserExecutable(
            System.IO.File.ReadAllBytes(imagePath));
        if (!executable.IsValid()) { return 44; }
        byte[] text = new byte[6];
        text[0] = 111; text[1] = 110; text[2] = 101;
        text[3] = 116; text[4] = 119; text[5] = 111;
        int[] starts = new int[2]; starts[1] = 3;
        int[] lengths = new int[2]; lengths[0] = 3; lengths[1] = 3;
        UserArguments arguments = new UserArguments(text, starts, lengths, 2);
        UserMockTerminal terminal = new UserMockTerminal(new byte[0]);
        UserProgramResult result = new UserProgramHost(terminal,
            new UserMockFiles()).Run(executable, arguments);
        byte[] expectedFirst = new byte[5];
        expectedFirst[0] = 111; expectedFirst[1] = 110;
        expectedFirst[2] = 101; expectedFirst[3] = 13; expectedFirst[4] = 10;
        byte[] expectedSecond = new byte[5];
        expectedSecond[0] = 116; expectedSecond[1] = 119;
        expectedSecond[2] = 111; expectedSecond[3] = 13; expectedSecond[4] = 10;
        if (result.Pid() != 1 || result.State() != UserProgramState.Exited() ||
            result.ExitCode() != 0 || result.Fault() != UserFault.None() ||
            !terminal.Contains(expectedFirst) || !terminal.Contains(expectedSecond)) {
            return 45;
        }
        System.Console.WriteLine("Userland stage 1 starter passed");
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
            if (args[0] == "stage1") { return CompiledStage1(args[1]); }
            if (args[0] == "stage1-starter") { return CompiledStage1Starter(args[1]); }
            if (args[0] == "shell-preview") { return CompiledShellPreview(args[1]); }
            if (args[0] == "shell-commands") { return CompiledShellCommands(args[1]); }
            if (args[0] == "system-launch") { return CompiledSystemLaunch(args[1]); }
            if (args[0] == "system-failure") { return CompiledSystemFailure(args[1]); }
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
        long[] duplicatePointers = new long[2];
        duplicatePointers[0] = recordBase + 320;
        duplicatePointers[1] = recordBase + 320;
        int[] duplicateLengths = new int[2];
        duplicateLengths[0] = 3; duplicateLengths[1] = 3;
        if (new UserArguments(startMemory, duplicatePointers,
            duplicateLengths, 2).IsValid()) { return 41; }
        UserMockFiles processFiles = new UserMockFiles();
        int[] processInformation = new int[46];
        UserProgramHost processHost = new UserProgramHost(
            new UserMockTerminal(new byte[0]), processFiles, processInformation);
        UserExecutable arithmeticImage = new UserExecutable(UserImages.ArithmeticLoop());
        int firstPid = processHost.SpawnForeground(arithmeticImage,
            new UserProcessStart(new UserArguments(new byte[0],
                new int[0], new int[0], 0)));
        if (firstPid != 1 || processInformation[40] != firstPid ||
            processHost.SpawnForeground(arithmeticImage,
                new UserProcessStart(startArguments)) != -1 ||
            processHost.Wait(2).Pid() != 0) { return 36; }
        UserProgramResult waited = processHost.Wait(firstPid);
        if (waited.Pid() != 1 || processInformation[40] != 0 ||
            waited.State() != UserProgramState.Exited() ||
            waited.ExitCode() != 15 || !processFiles.CloseAllCalled()) { return 37; }
        int secondPid = processHost.SpawnForeground(arithmeticImage,
            new UserProcessStart(startArguments));
        waited = processHost.Wait(secondPid);
        if (secondPid != 2 || waited.Pid() != 2 || waited.ExitCode() != 15) { return 38; }
        UserMockFiles runnableFilesA = new UserMockFiles();
        UserMockFiles runnableFilesB = new UserMockFiles();
        UserProgramHost runnableHost = new UserProgramHost(
            new UserMockTerminal(new byte[0]), new UserMockFiles());
        UserProcessStart runnableStart = new UserProcessStart(
            new UserArguments(new byte[0], new int[0], new int[0], 0));
        int runnableA = runnableHost.SpawnRunnable(arithmeticImage, runnableStart,
            runnableFilesA);
        int runnableB = runnableHost.SpawnRunnable(arithmeticImage, runnableStart,
            runnableFilesB);
        if (runnableA != 1 || runnableB != 2 || runnableHost.RunRound() != 2 ||
            runnableHost.Instructions(runnableA) < 1 ||
            runnableHost.Instructions(runnableB) < 1) { return 46; }
        if (runnableHost.Wait(runnableA).ExitCode() != 15 ||
            runnableHost.Wait(runnableB).ExitCode() != 15 ||
            !runnableFilesA.CloseAllCalled() || !runnableFilesB.CloseAllCalled()) {
            return 47;
        }
        int[] parentInformation = new int[55];
        int[] childInformation = new int[55];
        UserProgramHost blockedHost = new UserProgramHost(
            new UserMockTerminal(new byte[0]), new UserMockFiles(),
            parentInformation);
        int blockedParent = blockedHost.SpawnRunnable(arithmeticImage,
            runnableStart, new UserMockFiles());
        int blockedChild = blockedHost.SpawnRunnable(arithmeticImage,
            runnableStart, new UserMockFiles(), childInformation);
        if (!blockedHost.Block(blockedParent) || blockedHost.RunRound() != 1 ||
            blockedHost.Instructions(blockedParent) != 0 ||
            blockedHost.Instructions(blockedChild) < 1 ||
            parentInformation[40] != blockedParent ||
            childInformation[40] != blockedChild ||
            blockedHost.Wait(blockedChild).ExitCode() != 15 ||
            parentInformation[40] != blockedParent) { return 57; }
        blockedHost.Unblock(blockedParent);
        if (blockedHost.Wait(blockedParent).ExitCode() != 15) { return 58; }
        UserMockFiles supervisedFiles = new UserMockFiles();
        UserProgramHost supervisedHost = new UserProgramHost(
            new UserMockTerminal(new byte[0]), new UserMockFiles());
        int supervisedPid = supervisedHost.SpawnRunnable(arithmeticImage,
            runnableStart, supervisedFiles);
        if (supervisedPid != 1 || supervisedHost.WaitReady(supervisedPid, 1) != -2 ||
            supervisedHost.MarkReady(supervisedPid) != 0 ||
            supervisedHost.WaitReady(supervisedPid, 1) != 0 ||
            supervisedHost.Terminate(supervisedPid) != 0 ||
            supervisedHost.Wait(supervisedPid).Fault() != UserFault.Terminated() ||
            !supervisedFiles.CloseAllCalled()) { return 60; }
        UserProgramHost sleepingHost = new UserProgramHost(
            new UserMockTerminal(new byte[0]), new UserMockFiles());
        int sleepingPid = sleepingHost.SpawnRunnable(arithmeticImage,
            runnableStart, new UserMockFiles());
        if (sleepingPid != 1 || sleepingHost.Sleep(sleepingPid, 3) != 0 ||
            sleepingHost.RunRound() != 1 || sleepingHost.RunRound() != 1 ||
            sleepingHost.Instructions(sleepingPid) != 0 ||
            sleepingHost.RunRound() != 1 ||
            sleepingHost.Instructions(sleepingPid) < 1 ||
            sleepingHost.Wait(sleepingPid).ExitCode() != 15) { return 61; }
        UserProcessTable table = new UserProcessTable();
        if (!table.Start(1, 0, 1) || !table.Start(2, 1) ||
            !table.WaitForChild(1, 2) || table.Find(1).State() != 4 ||
            table.Find(2).ParentPid() != 1 || table.Start(2, 1) ||
            table.ActiveCount() != 2) { return 48; }
        UserChannelTable channels = new UserChannelTable(table);
        int channel = channels.Open(1, 2, 1);
        byte[] message = new byte[2]; message[0] = 65; message[1] = 66;
        byte[] reply = new byte[2];
        if (channel < 1 || channels.Open(2, 1, 1) != -2 ||
            channels.Accept(2, 2) != -1 || channels.Accept(2, 1) != channel ||
            channels.Peer(channel, 2) != 1 ||
            channels.Send(channel, 3, 1, message, 2) != -2 ||
            channels.Send(channel, 1, 2, message, 2) != -3 ||
            channels.Send(channel, 1, 1, message, 2) != 0 ||
            channels.Queued(channel, 2) != 1 ||
            channels.QueuedFor(channel, 1) != 0 ||
            channels.QueuedFor(channel, 2) != 1) { return 50; }
        message[0] = 90;
        if (channels.Receive(channel, 2, reply) != 2 || reply[0] != 65 ||
            reply[1] != 66 || channels.Receive(channel, 2, reply) != -1) {
            return 51;
        }
        if (channels.Send(channel, 1, 1, message, 2) != 0 ||
            channels.Send(channel, 1, 1, message, 2) != 0 ||
            channels.Send(channel, 1, 1, message, 2) != 0 ||
            channels.Send(channel, 1, 1, message, 2) != 0 ||
            channels.Send(channel, 1, 1, message, 2) != -5 ||
            channels.Queued(channel, 1) != 4 ||
            channels.Receive(channel, 2, new byte[1]) != -4 ||
            channels.Queued(channel, 2) != 4) { return 52; }
        channels.CloseForProcess(2);
        int replacement = channels.Open(1, 2, 1);
        if (channels.Queued(channel, 1) != -1 || replacement == channel ||
            channels.Queued(replacement, 1) != 0 ||
            channels.Receive(channel, 2, reply) != -1) { return 53; }
        int channelRound = 0;
        while (channelRound < 100) {
            if (!channels.Close(replacement, 1)) { return 58; }
            replacement = channels.Open(1, 2, 1);
            if (replacement < 1 || channels.Send(replacement, 1, 1,
                message, 2) != 0 || channels.Receive(replacement, 2, reply) != 2) {
                return 59;
            }
            channelRound = channelRound + 1;
        }
        if (!table.Finish(new UserProgramResult(2, UserProgramState.Exited(),
                7, UserFault.None(), 42)) || !table.Resume(1) ||
            table.Find(2).ExitCode() != 7 || table.Find(2).Instructions() != 42 ||
            table.ActiveCount() != 1 ||
            !table.Finish(new UserProgramResult(1, UserProgramState.Exited(),
                0, UserFault.None(), 10))) { return 49; }
        int recycledPid = 3;
        while (recycledPid <= 70) {
            if (!table.Start(recycledPid, 0) ||
                !table.Finish(new UserProgramResult(recycledPid,
                    UserProgramState.Exited(), 0, UserFault.None(), 1))) {
                return 56;
            }
            recycledPid = recycledPid + 1;
        }
        if (table.Find(70) == null || table.Find(70).State() !=
            UserProgramState.Exited() || table.Find(1) != null) { return 57; }
        UserProcessTable pendingWait = new UserProcessTable();
        if (!pendingWait.Start(1, 0) || !pendingWait.Start(2, 1) ||
            !pendingWait.Finish(new UserProgramResult(2,
                UserProgramState.Exited(), 19, UserFault.None(), 1))) {
            return 82;
        }
        int historyPid = 3;
        while (historyPid <= 70) {
            if (!pendingWait.Start(historyPid, 0) ||
                !pendingWait.Finish(new UserProgramResult(historyPid,
                    UserProgramState.Exited(), 0, UserFault.None(), 1))) {
                return 83;
            }
            historyPid = historyPid + 1;
        }
        if (pendingWait.Find(2) == null ||
            pendingWait.Find(2).ExitCode() != 19 ||
            !pendingWait.ReapChild(1, 2) ||
            pendingWait.ReapChild(1, 2) ||
            pendingWait.WaitForChild(1, 2)) { return 84; }
        UserSystemCalls checkedCalls = new UserSystemCalls(
            new UserMockTerminal(new byte[0]), new UserMockFiles(), 7);
        UserSyscallResult information = checkedCalls.SystemInformation(3);
        UserSyscallResult unavailableSystem = checkedCalls.SystemInformation(16);
        UserSyscallResult invalidInformation = checkedCalls.SystemInformation(99);
        UserSyscallResult opened = checkedCalls.OpenResult(startMemory,
            UserAddressSpace.DataBase() + 48, 10, false);
        if (information.Status() != UserSyscallStatus.Success() ||
            information.Value() != 7 ||
            unavailableSystem.Status() != UserSyscallStatus.InvalidArgument() ||
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
        byte[] panicCommand = new byte[5];
        panicCommand[0] = 112; panicCommand[1] = 97; panicCommand[2] = 110;
        panicCommand[3] = 105; panicCommand[4] = 99;
        parsed = new UserShellRegistry().Parse(panicCommand, panicCommand.Length);
        if (parsed.Identifier() != UserShellCommandId.Panic() || parsed.HasArgument()) { return 7; }
        System.Console.WriteLine("Australis user runtime tests passed");
        return 0;
    }
}
