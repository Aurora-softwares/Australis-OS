using Australis.Kernel.Storage;

namespace Australis.User {
    // Terminal syscalls use this byte contract on both the hosted tests and
    // the live kernel. ReadByte is called only from scheduler context; an IRQ
    // handler may fill a device queue, but it never executes a user program.
    public interface IUserTerminal {
        int ReadByte();
        bool WriteByte(int value);
    }

    // Descriptors 0, 1, and 2 are owned by UserSystemCalls. Implementations
    // of this interface provide read-only descriptors beginning at 3.
    public interface IUserFiles {
        int Open(byte[] path, int count);
        int Read(int descriptor, byte[] destination, int capacity);
        bool Close(int descriptor);
        void CloseAll();
    }

    public class UserProgramState {
        public static int Running() { return 1; }
        public static int Exited() { return 2; }
        public static int Faulted() { return 3; }
    }

    public class UserFault {
        public static int None() { return 0; }
        public static int InvalidImage() { return 1; }
        public static int InvalidInstruction() { return 2; }
        public static int MemoryAccess() { return 3; }
        public static int SystemCall() { return 4; }
        public static int InstructionLimit() { return 5; }
    }

    // AUEX v1 is a compact, deterministic bytecode image. It intentionally
    // has no instruction that can address physical memory. Code is read-only,
    // data is a separate bounded region, and every syscall copies through the
    // checked UserAddressSpace API.
    public class UserExecutable {
        private bool valid;
        private int status;
        private byte[] code;
        private byte[] initialData;
        private int dataCapacity;
        private int entry;

        public UserExecutable(byte[] image) {
            valid = false; status = UserFault.InvalidImage();
            code = new byte[0]; initialData = new byte[0]; dataCapacity = 0; entry = 0;
            if (image == null || image.Length < 32 || image[0] != 65 || image[1] != 85 ||
                image[2] != 69 || image[3] != 88 || image[4] != 1 || image[5] != 32 ||
                image[6] != 0 || image[7] != 0) { return; }
            long codeLengthLong = PartitionBytes.Read32(image, 8);
            long dataLengthLong = PartitionBytes.Read32(image, 12);
            long capacityLong = PartitionBytes.Read32(image, 16);
            long entryLong = PartitionBytes.Read32(image, 20);
            if (codeLengthLong < 1 || codeLengthLong > 65536 || dataLengthLong < 0 ||
                dataLengthLong > 65536 || capacityLong < dataLengthLong || capacityLong > 65536 ||
                entryLong < 0 || entryLong >= codeLengthLong ||
                codeLengthLong + dataLengthLong != image.Length - 32) { return; }
            int codeLength = (int)codeLengthLong;
            int dataLength = (int)dataLengthLong;
            if (PartitionBytes.Crc32(image, 32, codeLength, codeLength, 0) !=
                    PartitionBytes.Read32(image, 24) ||
                PartitionBytes.Crc32(image, 32 + codeLength, dataLength, dataLength, 0) !=
                    PartitionBytes.Read32(image, 28)) { return; }
            code = new byte[codeLength];
            initialData = new byte[dataLength];
            int i = 0;
            while (i < codeLength) { code[i] = image[32 + i]; i = i + 1; }
            i = 0;
            while (i < dataLength) { initialData[i] = image[32 + codeLength + i]; i = i + 1; }
            dataCapacity = (int)capacityLong;
            entry = (int)entryLong;
            valid = true; status = UserFault.None();
        }

        public bool IsValid() { return valid; }
        public int Status() { return status; }
        public byte[] Code() { return code; }
        public byte[] InitialData() { return initialData; }
        public int DataCapacity() { return dataCapacity; }
        public int Entry() { return entry; }
    }

    public class UserAddressSpace {
        private byte[] code;
        private byte[] data;

        public static long CodeBase() { return 4194304; }
        public static long DataBase() { return 5242880; }

        public UserAddressSpace(UserExecutable executable) {
            code = new byte[executable.Code().Length];
            data = new byte[executable.DataCapacity()];
            int i = 0;
            while (i < code.Length) { code[i] = executable.Code()[i]; i = i + 1; }
            i = 0;
            while (i < executable.InitialData().Length) {
                data[i] = executable.InitialData()[i]; i = i + 1;
            }
        }

        public int CodeLength() { return code.Length; }
        public int DataLength() { return data.Length; }
        public int ReadCode(int offset) {
            if (offset < 0 || offset >= code.Length) { return -1; }
            return code[offset];
        }
        public bool CanRead(long address, int count) {
            if (count < 0 || address < DataBase()) { return false; }
            long offset = address - DataBase();
            return offset <= data.Length && count <= data.Length - offset;
        }
        public bool CanWrite(long address, int count) { return CanRead(address, count); }
        public int ReadByte(long address) {
            if (!CanRead(address, 1)) { return -1; }
            return data[(int)(address - DataBase())];
        }
        public bool WriteByte(long address, int value) {
            if (value < 0 || value > 255 || !CanWrite(address, 1)) { return false; }
            data[(int)(address - DataBase())] = (byte)value;
            return true;
        }
        public bool CopyOut(long address, byte[] destination, int count) {
            if (destination == null || count < 0 || count > destination.Length ||
                !CanRead(address, count)) { return false; }
            int offset = (int)(address - DataBase());
            int i = 0;
            while (i < count) { destination[i] = data[offset + i]; i = i + 1; }
            return true;
        }
        public bool CopyIn(long address, byte[] source, int count) {
            if (source == null || count < 0 || count > source.Length ||
                !CanWrite(address, count)) { return false; }
            int offset = (int)(address - DataBase());
            int i = 0;
            while (i < count) { data[offset + i] = source[i]; i = i + 1; }
            return true;
        }
    }

    public class UserSystemCalls {
        private IUserTerminal terminal;
        private IUserFiles files;

        public UserSystemCalls(IUserTerminal inputTerminal, IUserFiles inputFiles) {
            terminal = inputTerminal;
            files = inputFiles;
        }

        public int Write(int descriptor, UserAddressSpace memory, long address, int count) {
            if ((descriptor != 1 && descriptor != 2) || terminal == null || memory == null ||
                count < 0 || !memory.CanRead(address, count)) { return -1; }
            int i = 0;
            while (i < count) {
                int value = memory.ReadByte(address + i);
                if (value < 0 || !terminal.WriteByte(value)) { return -1; }
                i = i + 1;
            }
            return count;
        }

        // fd 0 is a canonical terminal stream. Backspace editing and echo are
        // part of the terminal syscall, so every user program sees the same
        // behavior regardless of whether bytes came from COM1 or USB HID.
        public int ReadTerminal(UserAddressSpace memory, long address, int capacity) {
            if (terminal == null || memory == null || capacity < 1 ||
                !memory.CanWrite(address, capacity)) { return -1; }
            int length = 0;
            while (true) {
                int value = terminal.ReadByte();
                if (value < 0) { return -1; }
                if (value == 3) { return -2; }
                if (value == 10 || value == 13) {
                    terminal.WriteByte(13); terminal.WriteByte(10); return length;
                }
                if (value == 8 || value == 127) {
                    if (length > 0) {
                        length = length - 1;
                        terminal.WriteByte(8); terminal.WriteByte(32); terminal.WriteByte(8);
                    }
                } else if (value >= 32 && value <= 126 && length < capacity) {
                    if (!memory.WriteByte(address + length, value)) { return -1; }
                    length = length + 1; terminal.WriteByte(value);
                } else if (value >= 32 && value <= 126) {
                    terminal.WriteByte(7);
                }
            }
            return -1;
        }

        public int Open(UserAddressSpace memory, long address, int count) {
            if (memory == null || count < 1 || count > 255 || !memory.CanRead(address, count)) {
                return -1;
            }
            byte[] bytes = new byte[count];
            if (!memory.CopyOut(address, bytes, count)) { return -1; }
            if (files == null) { return -1; }
            return files.Open(bytes, count);
        }
        public int ReadFile(int descriptor, UserAddressSpace memory, long address, int capacity) {
            if (files == null || memory == null || capacity < 0 ||
                !memory.CanWrite(address, capacity)) { return -1; }
            byte[] bytes = new byte[capacity];
            int count = files.Read(descriptor, bytes, capacity);
            if (count < 0 || count > capacity || !memory.CopyIn(address, bytes, count)) { return -1; }
            return count;
        }
        public bool Close(int descriptor) { return files != null && files.Close(descriptor); }
        public void CloseAll() { if (files != null) { files.CloseAll(); } }
    }

    public class UserProcess {
        private UserAddressSpace memory;
        private UserSystemCalls calls;
        private int instructionPointer;
        private int state;
        private int fault;
        private int exitCode;
        private int accumulator;
        private int openDescriptor;
        private long instructions;

        public UserProcess(UserExecutable executable, UserSystemCalls systemCalls) {
            calls = systemCalls; instructionPointer = 0; fault = UserFault.InvalidImage();
            exitCode = -1; accumulator = 0; openDescriptor = -1; instructions = 0;
            if (executable == null || !executable.IsValid() || calls == null) {
                memory = null; state = UserProgramState.Faulted(); return;
            }
            memory = new UserAddressSpace(executable);
            instructionPointer = executable.Entry(); state = UserProgramState.Running();
            fault = UserFault.None();
        }

        public int State() { return state; }
        public int Fault() { return fault; }
        public int ExitCode() { return exitCode; }
        public int Accumulator() { return accumulator; }
        public long Instructions() { return instructions; }
        public UserAddressSpace AddressSpace() { return memory; }
        public void Abort(int cause) {
            if (state == UserProgramState.Running()) { Fail(cause); }
        }

        private void Fail(int cause) {
            fault = cause; state = UserProgramState.Faulted(); calls.CloseAll();
        }
        private int NextByte() {
            if (memory == null) { return -1; }
            int value = memory.ReadCode(instructionPointer);
            if (value >= 0) { instructionPointer = instructionPointer + 1; }
            return value;
        }
        private long Next32() {
            int b0 = NextByte(); int b1 = NextByte(); int b2 = NextByte(); int b3 = NextByte();
            if (b0 < 0 || b1 < 0 || b2 < 0 || b3 < 0) { return -1; }
            return b0 + b1 * 256 + b2 * 65536 + (long)b3 * 16777216;
        }

        // Execute at most one bytecode operation. Returning to the scheduler
        // after each operation bounds latency and gives explicit yield points.
        public void Step() {
            if (state != UserProgramState.Running()) { return; }
            int opcode = NextByte();
            if (opcode < 0) { Fail(UserFault.InvalidInstruction()); return; }
            instructions = instructions + 1;
            if (opcode == 1) {
                int code = NextByte();
                if (code < 0) { Fail(UserFault.InvalidInstruction()); return; }
                exitCode = code; state = UserProgramState.Exited(); calls.CloseAll(); return;
            }
            if (opcode == 2) {
                long address = Next32(); long count = Next32();
                if (address < 0 || count < 0 || count > 65536 ||
                    calls.Write(1, memory, address, (int)count) < 0) {
                    Fail(UserFault.SystemCall());
                }
                return;
            }
            if (opcode == 3) {
                long address = Next32(); long capacity = Next32();
                if (address < 0 || capacity < 1 || capacity > 65536) {
                    Fail(UserFault.InvalidInstruction()); return;
                }
                accumulator = calls.ReadTerminal(memory, address, (int)capacity);
                if (accumulator < 0) { Fail(UserFault.SystemCall()); }
                return;
            }
            if (opcode == 4) {
                long address = Next32();
                if (address < 0 || accumulator < 0 ||
                    calls.Write(1, memory, address, accumulator) < 0) {
                    Fail(UserFault.SystemCall());
                }
                return;
            }
            if (opcode == 5) {
                long address = Next32(); long count = Next32();
                if (address < 0 || count < 1 || count > 255) {
                    Fail(UserFault.InvalidInstruction()); return;
                }
                openDescriptor = calls.Open(memory, address, (int)count);
                if (openDescriptor < 0) { Fail(UserFault.SystemCall()); }
                return;
            }
            if (opcode == 6) {
                long address = Next32(); long capacity = Next32();
                if (address < 0 || capacity < 0 || capacity > 65536 || openDescriptor < 3) {
                    Fail(UserFault.InvalidInstruction()); return;
                }
                accumulator = calls.ReadFile(openDescriptor, memory, address, (int)capacity);
                if (accumulator < 0) { Fail(UserFault.SystemCall()); }
                return;
            }
            if (opcode == 7) {
                if (openDescriptor < 3 || !calls.Close(openDescriptor)) {
                    Fail(UserFault.SystemCall()); return;
                }
                openDescriptor = -1; return;
            }
            if (opcode == 8) {
                long address = Next32(); int value = NextByte();
                if (address < 0 || value < 0 || !memory.WriteByte(address, value)) {
                    Fail(UserFault.MemoryAccess());
                }
                return;
            }
            if (opcode == 9) { return; }
            if (opcode == 10) {
                long target = Next32();
                if (target < 0 || target >= memory.CodeLength()) {
                    Fail(UserFault.InvalidInstruction()); return;
                }
                instructionPointer = (int)target; return;
            }
            Fail(UserFault.InvalidInstruction());
        }
    }

    public class UserProgramResult {
        private int state;
        private int exitCode;
        private int fault;
        private long instructions;
        public UserProgramResult(int inputState, int inputExit, int inputFault, long inputInstructions) {
            state = inputState; exitCode = inputExit; fault = inputFault; instructions = inputInstructions;
        }
        public int State() { return state; }
        public int ExitCode() { return exitCode; }
        public int Fault() { return fault; }
        public long Instructions() { return instructions; }
    }

    public class UserScheduler {
        private int quantum;
        private long instructionLimit;
        public UserScheduler() { quantum = 32; instructionLimit = 100000; }

        public UserProgramResult Run(UserProcess process) {
            if (process == null) {
                return new UserProgramResult(UserProgramState.Faulted(), -1,
                    UserFault.InvalidImage(), 0);
            }
            while (process.State() == UserProgramState.Running() &&
                process.Instructions() < instructionLimit) {
                int used = 0;
                while (used < quantum && process.State() == UserProgramState.Running()) {
                    process.Step(); used = used + 1;
                }
            }
            if (process.State() == UserProgramState.Running()) {
                process.Abort(UserFault.InstructionLimit());
            }
            return new UserProgramResult(process.State(), process.ExitCode(),
                process.Fault(), process.Instructions());
        }
    }

    public class UserProgramHost {
        private IUserTerminal terminal;
        private IUserFiles files;
        public UserProgramHost(IUserTerminal inputTerminal, IUserFiles inputFiles) {
            terminal = inputTerminal; files = inputFiles;
        }

        public UserProgramResult Run(UserExecutable executable) {
            if (executable == null) {
                return new UserProgramResult(UserProgramState.Faulted(), -1,
                    UserFault.InvalidImage(), 0);
            }
            UserSystemCalls calls = new UserSystemCalls(terminal, files);
            UserProcess process = new UserProcess(executable, calls);
            return new UserScheduler().Run(process);
        }
    }
}
