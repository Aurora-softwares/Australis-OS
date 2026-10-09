using Australis.Kernel.Vfs;

namespace Australis.Kernel.Console {
    // The PC-compatible 16550 at COM1 uses receive-data interrupts on legacy
    // PIC IRQ4. The interrupt drains the FIFO into a fixed ring; the shell
    // consumes that ring, keeping the handler allocation-free and safe at any
    // instruction.
    public class SerialPort {
        private int basePort;
        private long bootInfo;
        private bool ready;
        private bool receiveInterrupts;

        public SerialPort(int inputBasePort, long inputBootInfo) {
            basePort = inputBasePort;
            bootInfo = inputBootInfo;
            ready = false;
            receiveInterrupts = false;
        }

        public bool Initialize() {
            if (basePort < 0 || basePort > 65528 || bootInfo < 4096) { return false; }
            int scratch = System.Kernel.Port.Read8(basePort + 7);
            System.Kernel.Port.Write8(basePort + 7, 90);
            bool present = System.Kernel.Port.Read8(basePort + 7) == 90;
            System.Kernel.Port.Write8(basePort + 7, scratch);
            if (!present) { return false; }

            System.Kernel.Port.Write8(basePort + 1, 0);   // no UART IRQs during setup
            System.Kernel.Port.Write8(basePort + 3, 128); // divisor latch
            System.Kernel.Port.Write8(basePort, 1);       // 115200 baud
            System.Kernel.Port.Write8(basePort + 1, 0);
            System.Kernel.Port.Write8(basePort + 3, 3);   // 8 data, no parity, 1 stop
            System.Kernel.Port.Write8(basePort + 2, 199); // FIFO on, clear RX/TX
            System.Kernel.Port.Write8(basePort + 4, 3);   // DTR and RTS
            ready = System.Kernel.Port.Read8(basePort + 5) != 255;
            if (!ready) { return false; }

            // Clear a stale interrupt cause before exposing the PIC line, then
            // enable receiver-data-available only. Transmit interrupts remain
            // off because writes use bounded polling.
            // The IDT's IRQ4 handler owns this bounded 1024-byte ring. Clear
            // cursors before exposing receive interrupts to the PIC.
            System.Kernel.Memory.Write32(bootInfo + 1168, 0);
            System.Kernel.Memory.Write32(bootInfo + 1172, 0);
            System.Kernel.Memory.Write32(bootInfo + 1176, 0);
            int interruptCause = System.Kernel.Port.Read8(basePort + 2);
            System.Kernel.Port.Write8(basePort + 1, 1);
            int masterMask = System.Kernel.Port.Read8(33);
            if ((masterMask / 16) % 2 != 0) { masterMask = masterMask - 16; }
            System.Kernel.Port.Write8(33, masterMask); // unmask COM1 / IRQ4
            receiveInterrupts = true;
            return ready;
        }

        public bool IsReady() { return ready; }
        public bool ReceiveInterruptsEnabled() { return receiveInterrupts; }

        public bool WriteByte(int value) {
            if (!ready || value < 0 || value > 255) { return false; }
            int attempts = 0;
            while (attempts < 1000000) {
                int status = System.Kernel.Port.Read8(basePort + 5);
                if (status == 255) { ready = false; return false; }
                if ((status / 32) % 2 != 0) {
                    System.Kernel.Port.Write8(basePort, value);
                    return true;
                }
                System.Kernel.Cpu.Pause();
                attempts = attempts + 1;
            }
            return false;
        }

        // -1 means the IRQ-fed ring is empty; -2 means the UART disappeared.
        public int PollByte() {
            if (!ready) { return -2; }
            int tail = System.Kernel.Memory.Read32(bootInfo + 1172);
            int head = System.Kernel.Memory.Read32(bootInfo + 1168);
            if (tail < 0 || tail > 1023 || head < 0 || head > 1023) { ready = false; return -2; }
            if (tail == head) { return -1; }
            int value = System.Kernel.Memory.Read8(bootInfo + 1280 + tail);
            tail = (tail + 1) % 1024;
            System.Kernel.Memory.Write32(bootInfo + 1172, tail);
            return value;
        }

        public bool WriteText(string text) {
            if (text == null) { return false; }
            int i = 0;
            while (i < text.Length) {
                if (!WriteByte(System.Kernel.String.ByteAt(text, i))) { return false; }
                i = i + 1;
            }
            return true;
        }

        public bool WriteLine(string text) {
            return WriteText(text) && WriteByte(13) && WriteByte(10);
        }

        public bool WriteBytes(byte[] bytes, int count) {
            if (bytes == null || count < 0 || count > bytes.Length) { return false; }
            int i = 0;
            while (i < count) {
                if (!WriteByte(bytes[i])) { return false; }
                i = i + 1;
            }
            return true;
        }
    }

    // A bounded command loop over the mounted read-only root. The line buffer
    // and command text are retained for the life of the loop, so ordinary
    // typing does not allocate a page for every received character.
    public class SerialShell {
        private SerialPort port;
        private Vfs root;
        private long bootInfo;
        private byte[] line;
        private byte[] nameBuffer;
        private int length;
        private bool overflow;
        private bool previousCr;
        private int commandCount;
        private string prompt;
        private string helpWord;
        private string echoWord;
        private string lsWord;
        private string catWord;
        private string versionWord;
        private string banner;
        private string helpText;
        private string unknownText;
        private string usageText;
        private string notFoundText;
        private string readErrorText;
        private string tooLargeText;
        private string overflowText;

        public SerialShell(SerialPort inputPort, Vfs inputRoot, long inputBootInfo) {
            port = inputPort;
            root = inputRoot;
            bootInfo = inputBootInfo;
            line = new byte[256];
            nameBuffer = new byte[32];
            length = 0;
            overflow = false;
            previousCr = false;
            commandCount = 0;
            prompt = "australis> ";
            helpWord = "help";
            echoWord = "echo";
            lsWord = "ls";
            catWord = "cat";
            versionWord = "version";
            banner = "Australis serial console ready. Type help.";
            helpText = "Commands: help, echo <text>, ls, cat <path>, version";
            unknownText = "Unknown command. Type help.";
            usageText = "Usage: cat /filename";
            notFoundText = "File not found.";
            readErrorText = "File read failed.";
            tooLargeText = "File exceeds the 64 KiB console limit.";
            overflowText = "Input line is too long.";
        }

        private bool StartsWith(string word) {
            if (length < word.Length) { return false; }
            int i = 0;
            while (i < word.Length) {
                if (line[i] != System.Kernel.String.ByteAt(word, i)) { return false; }
                i = i + 1;
            }
            return true;
        }

        private void NewLine() { port.WriteByte(13); port.WriteByte(10); }

        private void ListRoot() {
            int slots = root.RootDirectorySlotCount();
            if (slots < 0) { port.WriteLine(readErrorText); return; }
            int index = 0;
            while (index < slots) {
                int nameLength = root.CopyRootDirectoryEntryName(index, nameBuffer);
                if (nameLength < 0) { port.WriteLine(readErrorText); return; }
                if (nameLength > 0) {
                    port.WriteByte(47);
                    port.WriteBytes(nameBuffer, nameLength);
                    NewLine();
                }
                index = index + 1;
            }
        }

        private void Cat() {
            int start = catWord.Length;
            while (start < length && line[start] == 32) { start = start + 1; }
            int end = length;
            while (end > start && line[end - 1] == 32) { end = end - 1; }
            int pathLength = end - start;
            if (pathLength < 2 || pathLength > 33 || line[start] != 47) {
                port.WriteLine(usageText); return;
            }
            byte[] pathBytes = new byte[pathLength];
            int i = 0;
            while (i < pathLength) {
                pathBytes[i] = line[start + i];
                i = i + 1;
            }
            string path = System.Kernel.String.FromBytes(pathBytes, pathLength);
            VfsFileInfo info = root.StatRootFile(path);
            if (!info.Exists()) {
                if (info.Status() == VfsStatus.NotFound()) { port.WriteLine(notFoundText); }
                else { port.WriteLine(readErrorText); }
                return;
            }
            if (info.ByteLength() > 65536) { port.WriteLine(tooLargeText); return; }
            byte[] content = new byte[(int)info.ByteLength()];
            if (root.ReadRootFile(path, 0, content) != VfsStatus.Ok()) {
                port.WriteLine(readErrorText); return;
            }
            port.WriteBytes(content, content.Length);
            if (content.Length == 0 || content[content.Length - 1] != 10) { NewLine(); }
        }

        private void Execute() {
            commandCount = commandCount + 1;
            System.Kernel.Memory.Write32(bootInfo + 1144, commandCount);
            if (length == 0) { return; }
            if (overflow) { port.WriteLine(overflowText); return; }
            if (StartsWith(helpWord) && length == helpWord.Length) {
                port.WriteLine(helpText); return;
            }
            if (StartsWith(versionWord) && length == versionWord.Length) {
                port.WriteLine(banner); return;
            }
            if (StartsWith(lsWord) && length == lsWord.Length) {
                ListRoot(); return;
            }
            if (StartsWith(echoWord) && (length == echoWord.Length || line[echoWord.Length] == 32)) {
                int start = echoWord.Length;
                if (start < length) { start = start + 1; }
                int i = start;
                while (i < length) { port.WriteByte(line[i]); i = i + 1; }
                NewLine(); return;
            }
            if (StartsWith(catWord) && (length == catWord.Length || line[catWord.Length] == 32)) {
                Cat(); return;
            }
            port.WriteLine(unknownText);
        }

        private void EraseLast() {
            if (length == 0) { return; }
            length = length - 1;
            port.WriteByte(8); port.WriteByte(32); port.WriteByte(8);
        }

        public void Run() {
            if (!PhysicalPages.BeginTransientRegion(bootInfo)) {
                port.WriteLine(readErrorText);
                return;
            }
            port.WriteLine(banner);
            port.WriteText(prompt);
            while (port.IsReady()) {
                int value = port.PollByte();
                if (value == -1) { System.Kernel.Cpu.Halt(); continue; }
                if (value < 0) { continue; }
                if (value == 10 && previousCr) { previousCr = false; continue; }
                previousCr = value == 13;
                if (value == 13 || value == 10) {
                    NewLine();
                    long marker = PhysicalPages.MarkTransient(bootInfo);
                    Execute();
                    if (marker == 0 || !PhysicalPages.RewindTransient(bootInfo, marker)) {
                        port.WriteLine(readErrorText);
                        return;
                    }
                    length = 0; overflow = false;
                    port.WriteText(prompt);
                } else if (value == 8 || value == 127) {
                    EraseLast();
                } else if (value == 3 || value == 21) {
                    while (length > 0) { EraseLast(); }
                    overflow = false;
                    if (value == 3) { NewLine(); port.WriteText(prompt); }
                } else if (value >= 32 && value <= 126) {
                    if (length < line.Length && !overflow) {
                        line[length] = (byte)value;
                        length = length + 1;
                        port.WriteByte(value);
                    } else if (!overflow) {
                        overflow = true;
                        port.WriteByte(7);
                    }
                }
            }
        }
    }
}
