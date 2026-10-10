using Australis.Kernel.Console;
using Australis.Kernel.Usb;
using Australis.Kernel.Vfs;

namespace Australis.User {
    // The live adapter consumes the same decoded event queue as the shell.
    // Controller work and ANSI decoding happen here in normal context; COM1
    // and xHCI handlers only acknowledge hardware and enqueue bounded input.
    public class NativeUserTerminal : IUserTerminal {
        private IConsoleInput input;
        private ConsoleWriter output;
        private ConsoleEventQueue events;
        private SerialKeyDecoder decoder;
        private NativeXhci usb;

        public NativeUserTerminal(IConsoleInput inputSource, ConsoleWriter outputWriter,
            ConsoleEventQueue inputEvents, SerialKeyDecoder inputDecoder, NativeXhci inputUsb) {
            input = inputSource; output = outputWriter; events = inputEvents;
            decoder = inputDecoder; usb = inputUsb;
        }

        public int ReadByte() {
            if (input == null || output == null || events == null || decoder == null) { return -1; }
            while (input.IsReady()) {
                int value = events.Poll();
                if (value >= 0 && value <= 255) { return value; }
                if (value == ConsoleKey.InputLost()) { return -1; }
                if (usb != null) { usb.Pump(); }
                decoder.Pump();
                value = events.Poll();
                if (value >= 0 && value <= 255) { return value; }
                if (value == ConsoleKey.InputLost()) { return -1; }
                if (input.CanHalt()) { System.Kernel.Cpu.Halt(); }
                else { System.Kernel.Cpu.Pause(); }
            }
            return -1;
        }

        public bool WriteByte(int value) {
            return output != null && output.WriteByte(value);
        }
    }

    public class NativeUserFiles : IUserFiles {
        private VfsNamespace mounts;
        private VfsFileHandle[] handles;
        public NativeUserFiles(VfsNamespace inputMounts) {
            mounts = inputMounts; handles = new VfsFileHandle[16];
        }
        public int Open(byte[] path, int count) {
            if (mounts == null || path == null || count < 1 || count > path.Length) { return -1; }
            string text = System.Kernel.String.FromBytes(path, count);
            VfsFileHandle handle = mounts.Open(text);
            if (handle == null || !handle.IsOpen()) { return -1; }
            int descriptor = 3;
            while (descriptor < handles.Length && handles[descriptor] != null) {
                descriptor = descriptor + 1;
            }
            if (descriptor == handles.Length) { handle.Close(); return -1; }
            handles[descriptor] = handle; return descriptor;
        }
        public int Read(int descriptor, byte[] destination, int capacity) {
            if (descriptor < 3 || descriptor >= handles.Length || handles[descriptor] == null ||
                destination == null || capacity < 0 || capacity > destination.Length) { return -1; }
            VfsFileHandle handle = handles[descriptor];
            if (!handle.IsOpen()) { return -1; }
            int count = capacity;
            if (handle.Remaining() < count) { count = (int)handle.Remaining(); }
            if (count == 0) { return 0; }
            byte[] bytes = new byte[count];
            if (handle.Read(bytes) != VfsStatus.Ok()) { return -1; }
            int i = 0;
            while (i < count) { destination[i] = bytes[i]; i = i + 1; }
            return count;
        }
        public bool Close(int descriptor) {
            if (descriptor < 3 || descriptor >= handles.Length || handles[descriptor] == null) {
                return false;
            }
            handles[descriptor].Close(); handles[descriptor] = null; return true;
        }
        public void CloseAll() {
            int descriptor = 3;
            while (descriptor < handles.Length) {
                if (handles[descriptor] != null) {
                    handles[descriptor].Close(); handles[descriptor] = null;
                }
                descriptor = descriptor + 1;
            }
        }
    }

    public class NativeUserProgramHost {
        private VfsNamespace mounts;
        private IUserTerminal terminal;
        public NativeUserProgramHost(VfsNamespace inputMounts, IUserTerminal inputTerminal) {
            mounts = inputMounts; terminal = inputTerminal;
        }
        private UserExecutable Load(string path) {
            if (mounts == null || path == null) { return null; }
            VfsFileInfo info = mounts.Stat(path);
            if (!info.Exists() || info.ByteLength() < 32 || info.ByteLength() > 131104) { return null; }
            VfsFileHandle handle = mounts.Open(path);
            if (handle == null || !handle.IsOpen()) { return null; }
            byte[] image = new byte[(int)info.ByteLength()];
            if (handle.Read(image) != VfsStatus.Ok()) { handle.Close(); return null; }
            handle.Close();
            UserExecutable executable = new UserExecutable(image);
            if (!executable.IsValid()) { return null; }
            return executable;
        }
        public UserProgramResult Run(string path) {
            UserExecutable executable = Load(path);
            if (executable == null) {
                return new UserProgramResult(UserProgramState.Faulted(), -1,
                    UserFault.InvalidImage(), 0);
            }
            NativeUserFiles files = new NativeUserFiles(mounts);
            return new UserProgramHost(terminal, files).Run(executable);
        }
    }
}
