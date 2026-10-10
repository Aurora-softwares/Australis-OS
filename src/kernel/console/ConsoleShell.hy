using Australis.Kernel.Vfs;
using Australis.Kernel.Usb;

namespace Australis.Kernel.Console {
    // A bounded command loop over the mounted read-only root. The line buffer
    // and command text are retained for the life of the loop, so ordinary
    // typing does not allocate a page for every received character.
    public class ConsoleShell {
        private IConsoleInput input;
        private ConsoleWriter output;
        private Vfs root;
        private Vfs removable;
        private NativeXhci usb;
        private long bootInfo;
        private LineEditor editor;
        private ConsoleEventQueue events;
        private SerialKeyDecoder decoder;
        private byte[] line;
        private byte[] nameBuffer;
        private int length;
        private int commandCount;
        private string prompt;
        private string helpWord;
        private string echoWord;
        private string lsWord;
        private string catWord;
        private string versionWord;
        private string devicesWord;
        private string mountsWord;
        private string pwdWord;
		private string versionText;
        private string banner;
        private string helpText;
        private string unknownText;
        private string usageText;
        private string notFoundText;
        private string readErrorText;
        private string tooLargeText;
        private string overflowText;
        private string lostText;

        public ConsoleShell(IConsoleInput inputSource, ConsoleWriter outputWriter, Vfs inputRoot,
            Vfs inputRemovable, NativeXhci inputUsb, long inputBootInfo) {
            input = inputSource;
            output = outputWriter;
            root = inputRoot;
            removable = inputRemovable;
            usb = inputUsb;
            bootInfo = inputBootInfo;
            editor = new LineEditor();
            events = new ConsoleEventQueue();
            decoder = new SerialKeyDecoder(input, events);
            line = editor.Bytes();
            nameBuffer = new byte[32];
            length = 0;
            commandCount = 0;
            prompt = "australis> ";
            helpWord = "help";
            echoWord = "echo";
            lsWord = "ls";
            catWord = "cat";
            versionWord = "version";
            devicesWord = "devices";
            mountsWord = "mounts";
            pwdWord = "pwd";
            banner = "Australis serial console ready. Type help.";
            versionText = "version: 0.0.1";
            helpText = "Commands: help, echo, ls [mount], cat <path>, devices, mounts, pwd, version";
            unknownText = "Unknown command. Type help.";
            usageText = "Usage: cat /filename";
            notFoundText = "File not found.";
            readErrorText = "File read failed.";
            tooLargeText = "File exceeds the 64 KiB console limit.";
            overflowText = "Input line is too long.";
            lostText = "Input dropped. Retype command.";
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

        private void NewLine() { output.WriteByte(13); output.WriteByte(10); }

        private void ListVolume(Vfs volume, bool usbPrefix) {
            if (volume == null || !volume.IsRootMounted()) { output.WriteLine(notFoundText); return; }
            int slots = volume.RootDirectorySlotCount();
            if (slots < 0) { output.WriteLine(readErrorText); return; }
            int index = 0;
            while (index < slots) {
                int nameLength = volume.CopyRootDirectoryEntryName(index, nameBuffer);
                if (nameLength < 0) { output.WriteLine(readErrorText); return; }
                if (nameLength > 0) {
                    if (usbPrefix) { output.WriteText("/usb"); }
                    output.WriteByte(47);
                    output.WriteBytes(nameBuffer, nameLength);
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
                output.WriteLine(usageText); return;
            }
            bool useUsb = pathLength > 5 && line[start] == 47 && line[start + 1] == 117 &&
                line[start + 2] == 115 && line[start + 3] == 98 && line[start + 4] == 47;
            int sourceStart = start;
            int selectedLength = pathLength;
            Vfs volume = root;
            if (useUsb) { sourceStart = start + 4; selectedLength = pathLength - 4; volume = removable; }
            if (volume == null || !volume.IsRootMounted()) { output.WriteLine(notFoundText); return; }
            byte[] pathBytes = new byte[selectedLength];
            int i = 0;
            while (i < selectedLength) {
                pathBytes[i] = line[sourceStart + i];
                i = i + 1;
            }
            string path = System.Kernel.String.FromBytes(pathBytes, selectedLength);
            VfsFileInfo info = volume.StatRootFile(path);
            if (!info.Exists()) {
                if (info.Status() == VfsStatus.NotFound()) { output.WriteLine(notFoundText); }
                else { output.WriteLine(readErrorText); }
                return;
            }
            if (info.ByteLength() > 65536) { output.WriteLine(tooLargeText); return; }
            VfsFileHandle handle = volume.OpenRootFile(path);
            long remaining = info.ByteLength();
            int lastByte = -1;
            while (remaining > 0) {
                int count = 512; if (remaining < count) { count = (int)remaining; }
                byte[] content = new byte[count];
                if (handle.Read(content) != VfsStatus.Ok()) {
                    handle.Close(); output.WriteLine(readErrorText); return;
                }
                output.WriteBytes(content, content.Length);
                lastByte = content[content.Length - 1];
                remaining = remaining - count;
            }
            handle.Close();
            if (info.ByteLength() == 0 || lastByte != 10) { NewLine(); }
        }

        private void Devices() {
            output.WriteLine("boot0: system storage ready");
            if (usb == null) { output.WriteLine("usb0: absent"); }
            else if (usb.IsStorage()) { output.WriteLine("usb0: mass-storage ready"); }
            else if (usb.IsKeyboard()) { output.WriteLine("usb0: keyboard ready"); }
            else { output.WriteLine("usb0: removed or unavailable"); }
        }

        private void Mounts() {
            output.WriteLine("/: hyfs boot0");
            if (removable != null && removable.IsRootMounted()) {
                if (usb != null && usb.IsStorage()) { output.WriteLine("/usb: hyfs usb0"); }
                else { output.WriteLine("/usb: hyfs offline"); }
            }
        }

        private void Execute() {
            commandCount = commandCount + 1;
            System.Kernel.Memory.Write32(bootInfo + 1144, commandCount);
            if (editor.InputWasLost()) { output.WriteLine(lostText); return; }
            if (length == 0) { return; }
            if (editor.Overflowed()) { output.WriteLine(overflowText); return; }
            if (StartsWith(helpWord) && length == helpWord.Length) {
                output.WriteLine(helpText); return;
            }
            if (StartsWith(versionWord) && length == versionWord.Length) {
                output.WriteLine(versionText); return;
            }
            if (StartsWith(devicesWord) && length == devicesWord.Length) { Devices(); return; }
            if (StartsWith(mountsWord) && length == mountsWord.Length) { Mounts(); return; }
            if (StartsWith(pwdWord) && length == pwdWord.Length) { output.WriteLine("/"); return; }
            if (StartsWith(lsWord) && length == lsWord.Length) {
                ListVolume(root, false); return;
            }
            if (StartsWith(lsWord) && length == 7 && line[2] == 32 && line[3] == 47 &&
                line[4] == 117 && line[5] == 115 && line[6] == 98) {
                ListVolume(removable, true); return;
            }
            if (StartsWith(echoWord) && (length == echoWord.Length || line[echoWord.Length] == 32)) {
                int start = echoWord.Length;
                if (start < length) { start = start + 1; }
                int i = start;
                while (i < length) { output.WriteByte(line[i]); i = i + 1; }
                NewLine(); return;
            }
            if (StartsWith(catWord) && (length == catWord.Length || line[catWord.Length] == 32)) {
                Cat(); return;
            }
            output.WriteLine(unknownText);
        }

        private void Redraw() {
            output.ClearLine();
            output.WriteText(prompt);
            output.WriteBytes(line, length);
            int remaining = length - editor.Cursor();
            while (remaining > 0) { output.WriteByte(8); remaining = remaining - 1; }
        }

        // For deferred device notices, clear the active input row, print a
        // complete line, then restore the prompt and edited command.
        public void PrintNotice(string text) {
            output.ClearLine();
            output.WriteLine(text);
            Redraw();
        }

        private bool HandleKey(int value) {
            int action = editor.Apply(value);
            length = editor.Length();
            if (action == LineEditor.Submit()) {
                int remaining = length - editor.Cursor();
                while (remaining > 0) {
                    output.WriteByte(27); output.WriteByte(91); output.WriteByte(67);
                    remaining = remaining - 1;
                }
                NewLine();
                long marker = PhysicalPages.MarkTransient(bootInfo);
                Execute();
                editor.Commit();
                if (marker == 0 || !PhysicalPages.RewindTransient(bootInfo, marker)) {
                    output.WriteLine(readErrorText);
                    return false;
                }
                editor.Reset();
                length = 0;
                output.WriteText(prompt);
            } else if (action == LineEditor.Cancel()) {
                NewLine();
                editor.Reset();
                length = 0;
                output.WriteText(prompt);
            } else if (action == LineEditor.Append()) {
                output.WriteByte(value);
            } else if (action == LineEditor.EraseEnd()) {
                output.WriteByte(8); output.WriteByte(32); output.WriteByte(8);
            } else if (action == LineEditor.Redraw()) {
                Redraw();
            } else if (action == LineEditor.ClearScreen()) {
                output.ClearScreen();
                Redraw();
            } else if (action == LineEditor.Bell()) {
                output.WriteByte(7);
            }
            return true;
        }

        public void Run() {
            if (!PhysicalPages.BeginTransientRegion(bootInfo)) {
                output.WriteLine(readErrorText);
                return;
            }
            output.WriteLine(banner);
            output.WriteText(prompt);
            while (input.IsReady()) {
                decoder.Pump();
                System.Kernel.Memory.Write32(bootInfo + 1256, events.Dropped());
                int value = events.Poll();
                if (value == -1) {
                    if (input.CanHalt()) { System.Kernel.Cpu.Halt(); }
                    else { System.Kernel.Cpu.Pause(); }
                    continue;
                }
                if (!HandleKey(value)) { return; }
            }
        }
    }
}
