using Australis.Kernel.Console;

public class MockTerminalInput : IConsoleInput {
    private byte[] bytes;
    private int length;
    private int cursor;
    private int dropped;

    public MockTerminalInput(byte[] inputBytes, int inputLength) {
        bytes = inputBytes;
        length = inputLength;
        cursor = 0;
        dropped = 0;
    }

    public bool IsReady() { return true; }
    public int PollByte() {
        if (cursor == length) { return -1; }
        int value = bytes[cursor];
        cursor = cursor + 1;
        return value;
    }
    public int DroppedBytes() { return dropped; }
    public bool CanHalt() { return true; }
    public void DropOne() { dropped = dropped + 1; }
}

public class Program {
    public static int Main() {
        ConsoleEventQueue queue = new ConsoleEventQueue();
        int i = 0;
        while (i < 1023) {
            if (!queue.Enqueue(i)) { return 1; }
            i = i + 1;
        }
        if (queue.Enqueue(1023) || queue.Dropped() != 1 || queue.Pending() != 1023) { return 2; }
        i = 0;
        while (i < 1023) {
            if (queue.Poll() != i) { return 3; }
            i = i + 1;
        }
        if (queue.Poll() != -1 || queue.Pending() != 0) { return 4; }

        byte[] raw = new byte[13];
        raw[0] = 101; raw[1] = 99; raw[2] = 104; raw[3] = 111;
        raw[4] = 27; raw[5] = 91; raw[6] = 68; // left
        raw[7] = 27; raw[8] = 91; raw[9] = 51; raw[10] = 126; // delete
        raw[11] = 13; raw[12] = 10;
        MockTerminalInput input = new MockTerminalInput(raw, raw.Length);
        ConsoleEventQueue decoded = new ConsoleEventQueue();
        SerialKeyDecoder decoder = new SerialKeyDecoder(input, decoded);
        decoder.Pump();
        if (decoded.Poll() != 101 || decoded.Poll() != 99 || decoded.Poll() != 104 ||
            decoded.Poll() != 111 || decoded.Poll() != ConsoleKey.Left() ||
            decoded.Poll() != ConsoleKey.Delete() || decoded.Poll() != 13 ||
            decoded.Poll() != -1) { return 5; }
        input.DropOne();
        decoder.Pump();
        if (decoded.Poll() != ConsoleKey.InputLost()) { return 6; }

        LineEditor editor = new LineEditor();
        editor.Apply(101); editor.Apply(99); editor.Apply(104); editor.Apply(111);
        if (editor.Length() != 4 || editor.Cursor() != 4 || editor.ByteAt(3) != 111) { return 7; }
        editor.Apply(ConsoleKey.Left());
        editor.Apply(45); // insert before final o
        if (editor.Length() != 5 || editor.Cursor() != 4 || editor.ByteAt(3) != 45) { return 8; }
        editor.Apply(ConsoleKey.Delete());
        if (editor.Length() != 4 || editor.ByteAt(3) != 45) { return 9; }
        editor.Apply(8);
        if (editor.Length() != 3 || editor.ByteAt(2) != 104) { return 10; }
        editor.Apply(ConsoleKey.End());
        editor.Apply(111);
        editor.Commit();
        editor.Reset();
        editor.Apply(ConsoleKey.Up());
        if (editor.Length() != 4 || editor.ByteAt(0) != 101 || editor.ByteAt(3) != 111) { return 11; }
        editor.Apply(ConsoleKey.Down());
        if (editor.Length() != 0) { return 12; }
        editor.Apply(ConsoleKey.InputLost());
        if (!editor.InputWasLost()) { return 13; }
        editor.Apply(21);
        if (editor.InputWasLost()) { return 14; }
        i = 0;
        while (i < 256) { editor.Apply(120); i = i + 1; }
        if (editor.Length() != 256 || editor.Apply(120) != LineEditor.Bell() ||
            !editor.Overflowed()) { return 15; }
        editor.Reset();
        if (editor.Length() != 0 || editor.Overflowed()) { return 16; }
        System.Console.WriteLine("Australis terminal event and line editor tests passed");
        return 0;
    }
}
