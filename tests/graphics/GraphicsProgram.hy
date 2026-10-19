using Australis.Kernel.Console;
using Australis.Kernel.Graphics;
using Australis.Kernel.Pci;

public class MockVirtioPci : IPciConfigAccess {
    private long[] words;
    public MockVirtioPci() { words = new long[64]; }
    public long Read32(int bdf, int offset) {
        if (bdf != 7 || offset < 0 || offset >= 256 ||
            offset % 4 != 0) { return 0; }
        return words[offset / 4];
    }
    public void Write32(int bdf, int offset, long value) {
        if (bdf == 7 && offset >= 0 && offset < 256 &&
            offset % 4 == 0) { words[offset / 4] = value; }
    }
}

public class MockGpuControl : IVirtioGpuControl {
    private int[] commands;
    private int count;
    private int failAt;
    private long lastFence;
    private long lastTransferOffset;
    public MockGpuControl(int inputFailAt) {
        commands = new int[16]; count = 0; failAt = inputFailAt;
        lastFence = 0; lastTransferOffset = -1;
    }
    private long Read(byte[] bytes, int offset, int length) {
        long value = 0; long factor = 1; int i = 0;
        while (i < length) {
            value = value + (long)bytes[offset + i] * factor;
            if (i + 1 < length) { factor = factor * 256; }
            i = i + 1;
        }
        return value;
    }
    public bool Execute(byte[] request, int requestLength,
        int expectedResponseType) {
        if (request == null || requestLength < 24 ||
            requestLength > request.Length ||
            expectedResponseType != 4352 || count >= commands.Length ||
            Read(request, 4, 4) != 1 ||
            Read(request, 8, 8) <= lastFence) { return false; }
        lastFence = Read(request, 8, 8);
        int type = (int)Read(request, 0, 4);
        commands[count] = type;
        count = count + 1;
        if (type == 261) { lastTransferOffset = Read(request, 40, 8); }
        return count != failAt;
    }
    public int Count() { return count; }
    public int At(int index) { return commands[index]; }
    public long TransferOffset() { return lastTransferOffset; }
}

public class MockPixelWriter : IFramebufferPixelWriter {
    private long baseAddress;
    private int[] pixels;
    private int writes;
    public MockPixelWriter(long inputBase, int count) {
        baseAddress = inputBase;
        pixels = new int[count];
        writes = 0;
    }
    public bool WritePixel(long address, int value) {
        long offset = address - baseAddress;
        if (offset < 0 || offset % 4 != 0 || offset / 4 >= pixels.Length) {
            return false;
        }
        pixels[(int)(offset / 4)] = value;
        writes = writes + 1;
        return true;
    }
    public int Pixel(int index) { return pixels[index]; }
    public int Writes() { return writes; }
}

public class MockConsoleSink : IConsoleByteSink {
    private int writes;
    private int escapes;
    public MockConsoleSink() { writes = 0; escapes = 0; }
    public bool WriteByte(int value) {
        writes = writes + 1;
        if (value == 27) { escapes = escapes + 1; }
        return true;
    }
    public int Writes() { return writes; }
    public int Escapes() { return escapes; }
}

public class MockFrameClock : IFrameClock {
    private long ticks;
    public MockFrameClock() { ticks = 0; }
    public long Now() { return ticks; }
    public long TicksPerMillisecond() { return 1000; }
    public void Advance(long delta) { ticks = ticks + delta; }
}

public class MockNativeDisplayBackend : IDisplayBackend {
    private bool started;
    private bool failNext;
    private int presentations;
    private int lastPixel;
    public MockNativeDisplayBackend() {
        started = false; failNext = false;
        presentations = 0; lastPixel = -1;
    }
    public int Kind() { return 2; }
    public int Width() { return 8; }
    public int Height() { return 8; }
    public int StrideBytes() { return 32; }
    public int ScanoutFormat() { return 2; }
    public int Capabilities() { return 7; }
    public bool Initialize() { started = true; return true; }
    public bool Ready() { return started; }
    public void Shutdown() { started = false; }
    public bool Recover() { return Initialize(); }
    public bool PresentDamage(PixelSurface surface, DamageTracker damage) {
        if (!started || surface == null || damage == null) { return false; }
        if (failNext) { failNext = false; return false; }
        lastPixel = surface.Pixel(2, 2);
        presentations = presentations + 1;
        damage.Clear(); return true;
    }
    public bool FillImmediate(int x, int y, int width, int height,
        int rgb) { return started; }
    public void FailNext() { failNext = true; }
    public int Presentations() { return presentations; }
    public int LastPixel() { return lastPixel; }
}

public class Program {
    private static bool SameFrame(PixelSurface first, PixelSurface second) {
        if (first == null || second == null ||
            first.Width() != second.Width() ||
            first.Height() != second.Height()) { return false; }
        int y = 0;
        while (y < first.Height()) {
            int x = 0;
            while (x < first.Width()) {
                if (first.Pixel(x, y) != second.Pixel(x, y)) { return false; }
                x = x + 1;
            }
            y = y + 1;
        }
        return true;
    }
    public static int Main() {
        PixelSurface invalid = new PixelSurface(2048, 2048);
        if (invalid.Ready() || invalid.Fill(0)) { return 1; }
        PixelSurface canvas = new PixelSurface(8, 8);
        if (!canvas.Ready() || !canvas.Fill(0x112233) ||
            canvas.Pixel(7, 7) != 0x112233 || canvas.Pixel(8, 0) != -1 ||
            canvas.SetPixel(-1, 0, 0) || canvas.SetPixel(0, 0, -1)) { return 2; }
        if (!canvas.FillRect(-2, -1, 4, 3, 0xFF0000) ||
            canvas.Pixel(0, 0) != 0xFF0000 ||
            canvas.Pixel(1, 1) != 0xFF0000 ||
            canvas.Pixel(2, 0) != 0x112233 ||
            !canvas.FillRect(2147483647, 0, 4, 4, 0)) { return 3; }
        if (!canvas.FillRoundedRect(0, 0, 8, 8, 3, 0x00FF00) ||
            canvas.Pixel(0, 0) != 0xFF0000 ||
            canvas.Pixel(3, 0) != 0x00FF00 ||
            canvas.Pixel(7, 7) != 0x112233 ||
            canvas.Pixel(4, 4) != 0x00FF00) { return 4; }
        if (PixelSurface.BlendColor(0xFF0000, 0x0000FF, 128) != 0x80007F ||
            PixelSurface.BlendColor(0xFF0000, 0x0000FF, 0) != 0x0000FF ||
            PixelSurface.BlendColor(0xFF0000, 0x0000FF, 255) != 0xFF0000 ||
            PixelSurface.BlendColor(0, 0, 256) != -1) { return 5; }
        PixelSurface overlay = new PixelSurface(2, 2);
        overlay.Fill(0xFF0000);
        if (!canvas.Blit(overlay, 7, 7, 255) ||
            canvas.Pixel(7, 7) != 0xFF0000 ||
            canvas.Blit(canvas, 0, 0, 255) ||
            !canvas.Blit(overlay, 0, 0, 128) ||
            canvas.Pixel(0, 0) != 0xFF0000) { return 6; }
        PixelSurface sourceRegion = new PixelSurface(4, 4);
        PixelSurface targetRegion = new PixelSurface(4, 4);
        sourceRegion.Fill(0x234567); targetRegion.Fill(0x111111);
        sourceRegion.SetPixel(1, 1, 0xABCDEF);
        if (!targetRegion.CopyRegion(sourceRegion, 1, 1, 2, 2, 2, 2) ||
            targetRegion.Pixel(2, 2) != 0xABCDEF ||
            targetRegion.Pixel(3, 3) != 0x234567 ||
            targetRegion.Pixel(1, 2) != 0x111111 ||
            targetRegion.CopyRegion(sourceRegion, 3, 3, 0, 0, 2, 2) ||
            targetRegion.CopyRegion(targetRegion, 0, 0, 0, 0, 1, 1)) {
            return 49;
        }

        PixelSurface frame = new PixelSurface(2, 2);
        frame.Fill(0x0000FF);
        frame.SetPixel(0, 0, 0xFF0000);
        MockPixelWriter rgb = new MockPixelWriter(4096, 64);
        FramebufferPresenter rgbPresenter = new FramebufferPresenter(
            new FramebufferMode(4096, 256, 8, 8, 8, 0), rgb);
        if (!rgbPresenter.Ready() || rgbPresenter.Encode(0xFF0000) != 0x0000FF ||
            !rgbPresenter.Present(frame, 1, 1) || rgb.Writes() != 4 ||
            rgb.Pixel(9) != 0x0000FF || rgb.Pixel(10) != 0xFF0000 ||
            !rgbPresenter.Present(frame, -1, 3) || rgb.Writes() != 6 ||
            rgb.Pixel(24) != 0xFF0000 || rgb.Pixel(32) != 0xFF0000) { return 7; }
        MockPixelWriter bgr = new MockPixelWriter(8192, 64);
        FramebufferPresenter bgrPresenter = new FramebufferPresenter(
            new FramebufferMode(8192, 256, 8, 8, 8, 1), bgr);
        if (!bgrPresenter.Present(frame, 0, 0) ||
            bgr.Pixel(0) != 0xFF0000 || bgr.Pixel(1) != 0x0000FF ||
            !bgrPresenter.Present(frame, 2147483647, 0) || bgr.Writes() != 4) {
            return 8;
        }
        WindowLayout invalidLayout = new WindowLayout(100, 100, 32);
        WindowLayout layout = new WindowLayout(320, 240, 32);
        if (invalidLayout.Ready() || !layout.Ready() ||
            invalidLayout.Open(1, 0, 32, 120, 80) != -1 ||
            layout.Open(0, 0, 32, 120, 80) != -1 ||
            layout.Open(1, 0, 31, 120, 80) != -1) { return 9; }
        int first = layout.Open(10, 20, 48, 140, 100);
        int second = layout.Open(20, 60, 64, 140, 100);
        if (first < 1 || second <= first || layout.Count() != 2 ||
            layout.FocusedId() != second || layout.HitTest(70, 80) != second ||
            layout.HitTest(0, 0) != 0 || layout.TopBarMode() != 1 ||
            layout.Move(20, first, 30, 48) ||
            layout.Resize(10, first, 400, 100)) { return 10; }
        if (!layout.Focus(first) || layout.FocusedId() != first ||
            layout.HitTest(70, 80) != first ||
            !layout.Move(10, first, 24, 48) ||
            !layout.Resize(10, first, 150, 100) ||
            layout.HitTest(24, 48) != 0 ||
            layout.ControlAt(42, 64) != 1 ||
            layout.ControlAt(86, 64) != 3) { return 11; }
        if (!layout.Maximize(10, first) || layout.TopBarMode() != 2 ||
            layout.WindowAt(1).X() != 0 || layout.WindowAt(1).Y() != 32 ||
            layout.WindowAt(1).Width() != 320 ||
            layout.WindowAt(1).Height() != 208 ||
            layout.HitTest(18, 16) != first || layout.ControlAt(18, 16) != 1 ||
            layout.ControlAt(62, 16) != 3 ||
            layout.Move(10, first, 40, 48)) { return 12; }
        if (!layout.Minimize(10, first) || layout.TopBarMode() != 1 ||
            layout.FocusedId() != second || layout.HitTest(18, 16) != 0 ||
            !layout.RestoreMinimized(10, first) || layout.TopBarMode() != 2 ||
            !layout.Unmaximize(10, first) || layout.TopBarMode() != 1 ||
            layout.WindowAt(1).X() != 24 || layout.WindowAt(1).Width() != 150) {
            return 13;
        }
        if (layout.Close(20, first) || !layout.Close(10, first) ||
            layout.Count() != 1 || layout.FocusedId() != second ||
            layout.Focus(first) || layout.HitTest(70, 80) != second ||
            !layout.Close(20, second) || layout.FocusedId() != 0) { return 14; }
        WindowLayout cleanup = new WindowLayout(320, 240, 32);
        int owned = cleanup.Open(5, 0, 32, 120, 80);
        int other = cleanup.Open(6, 50, 50, 120, 80);
        int ownedAgain = cleanup.Open(5, 100, 80, 120, 80);
        if (owned < 1 || other < 1 || ownedAgain < 1 ||
            cleanup.CloseOwner(5) != 2 || cleanup.Count() != 1 ||
            cleanup.WindowAt(0).Id() != other || cleanup.CloseOwner(5) != 0) {
            return 15;
        }
        WindowLayout scene = new WindowLayout(320, 240, 32);
        int redWindow = scene.Open(10, 20, 48, 140, 100);
        int blueWindow = scene.Open(20, 60, 64, 140, 100);
        PixelSurface redContent = new PixelSurface(100, 60);
        PixelSurface blueContent = new PixelSurface(100, 60);
        redContent.Fill(0xCC3322); blueContent.Fill(0x2255CC);
        WindowRenderer renderer = new WindowRenderer(scene);
        if (!renderer.Ready() || renderer.Submit(20, redWindow, redContent) ||
            !renderer.Submit(10, redWindow, redContent) ||
            !renderer.Submit(20, blueWindow, blueContent)) { return 16; }
        redContent.Fill(0x00FF00); // Submitted pixels belong to the compositor.
        PixelSurface composed = renderer.Compose();
        if (composed == null || composed.Pixel(30, 80) != 0xCC3322 ||
            composed.Pixel(70, 100) != 0x2255CC ||
            composed.Pixel(20, 48) == 0xE1E6EC ||
            composed.Pixel(100, 10) == 0) { return 17; }
        renderer.Hover(78, 80);
        if (renderer.Compose().Pixel(78, 80) != 0x383838) { return 18; }
        renderer.Hover(-1, -1);
        if (!scene.Maximize(20, blueWindow) ||
            renderer.Compose().Pixel(100, 10) != 0 ||
            composed.Pixel(18, 16) != 0xFF5F57 ||
            composed.Pixel(70, 40) != 0x2255CC) { return 19; }
        if (!scene.Unmaximize(20, blueWindow) ||
            renderer.Compose().Pixel(100, 10) == 0 ||
            !scene.Minimize(20, blueWindow) ||
            renderer.Compose().Pixel(30, 80) != 0xCC3322 ||
            renderer.Remove(10, blueWindow) ||
            !renderer.Remove(20, blueWindow)) { return 20; }
        DamageTracker damage = new DamageTracker(8, 8);
        PixelSurface dirtyFrame = new PixelSurface(8, 8);
        dirtyFrame.Fill(0x123456);
        MockPixelWriter dirtyPixels = new MockPixelWriter(12288, 64);
        FramebufferPresenter dirtyPresenter = new FramebufferPresenter(
            new FramebufferMode(12288, 256, 8, 8, 8, 1), dirtyPixels);
        if (!damage.Add(-2, -2, 4, 4) || damage.Count() != 1 ||
            damage.At(0).Width() != 2 || damage.At(0).Height() != 2 ||
            !damage.Add(20, 20, 2, 2) || damage.Count() != 1 ||
            !dirtyPresenter.PresentDamage(dirtyFrame, damage) ||
            damage.Count() != 0 || dirtyPixels.Writes() != 4 ||
            dirtyPixels.Pixel(0) != 0x123456 || dirtyPixels.Pixel(2) != 0 ||
            dirtyPresenter.PresentRegion(dirtyFrame, 7, 7, 2, 2, 0, 0)) {
            return 21;
        }
        int d = 0;
        while (d < 17) { damage.Add(d % 8, d / 8, 1, 1); d = d + 1; }
        if (damage.Count() != 1 || damage.At(0).Width() != 8 ||
            damage.At(0).Height() != 8 ||
            !dirtyPresenter.PresentDamage(dirtyFrame, damage) ||
            dirtyPixels.Writes() != 68) { return 22; }
        WindowLayout routed = new WindowLayout(320, 240, 32);
        int appA = routed.Open(11, 10, 48, 120, 100);
        int appB = routed.Open(22, 150, 60, 120, 100);
        WindowRenderer routedRenderer = new WindowRenderer(routed);
        WindowInputRouter input = new WindowInputRouter(routed, routedRenderer);
        input.PointerDown(170, 100);
        input.Key(65);
        input.PointerMove(175, 105);
        input.PointerUp(175, 105);
        if (input.Poll(11) != null || input.Pending() != 4) { return 23; }
        WindowInputEvent event = input.Poll(22);
        if (event == null || event.Kind() != 2 || event.WindowId() != appB ||
            event.First() != 20 || event.Second() != 40) { return 24; }
        event = input.Poll(22);
        if (event == null || event.Kind() != 4 || event.First() != 65) { return 25; }
        event = input.Poll(22);
        if (event == null || event.Kind() != 1 || event.First() != 25 ||
            event.Second() != 45) { return 26; }
        event = input.Poll(22);
        if (event == null || event.Kind() != 3 || input.Pending() != 0) {
            return 27;
        }
        input.PointerDown(100, 60);
        input.PointerMove(120, 75);
        input.PointerUp(120, 75);
        if (routed.WindowAt(1).X() != 30 || routed.WindowAt(1).Y() != 63 ||
            routed.FocusedId() != appA || input.Pending() != 0) { return 28; }
        input.PointerDown(148, 161);
        input.PointerMove(158, 171);
        input.PointerUp(158, 171);
        if (routed.WindowAt(1).Width() != 130 ||
            routed.WindowAt(1).Height() != 110) { return 29; }
        input.PointerDown(70, 79); // Minimize app A.
        if (routed.FocusedId() != appB || routed.WindowAt(1).Visible()) {
            return 30;
        }
        input.Key(66);
        if (input.Poll(11) != null || input.Poll(22) == null) { return 31; }
        input.DropOwner(11);
        if (input.Poll(11) != null || input.Pending() != 0) { return 32; }
        input.PointerDown(212, 76);
        if (routed.TopBarMode() != 2 || routed.FocusedId() != appB ||
            routed.WindowAt(1).Y() != 32) { return 33; }
        input.PointerDown(62, 16);
        if (routed.TopBarMode() != 1 || routed.WindowAt(1).Y() != 60) {
            return 34;
        }
        input.PointerDown(168, 76);
        input.Key(67);
        if (routed.Count() != 1 || routed.FocusedId() != 0 ||
            input.Pending() != 0 || input.Poll(22) != null) { return 35; }
        WindowLayout exited = new WindowLayout(320, 240, 32);
        int exitedId = exited.Open(33, 20, 48, 120, 100);
        WindowInputRouter exitedInput = new WindowInputRouter(exited, null);
        exitedInput.PointerDown(40, 100);
        if (exitedInput.Pending() != 1 || !exited.Close(33, exitedId) ||
            exitedInput.Poll(33) != null || exitedInput.Pending() != 0) {
            return 36;
        }
        MockPixelWriter displayPixels = new MockPixelWriter(16384, 64);
        MockConsoleSink serialSink = new MockConsoleSink();
        MockConsoleSink mirrorSink = new MockConsoleSink();
        ConsoleWriter console = new ConsoleWriter(serialSink, mirrorSink);
        DisplayDevice display = new DisplayDevice(
            new FramebufferMode(16384, 256, 8, 8, 8, 0),
            displayPixels, console);
        DisplayBufferLayout gopLayout = display.BufferLayout();
        if (!display.Ready() || display.BackendKind() != 1 ||
            display.Width() != 8 || display.Height() != 8 ||
            display.StrideBytes() != 32 || display.ScanoutFormat() != 1 ||
            display.Capabilities() != 7 ||
            gopLayout == null || !gopLayout.Ready() ||
            gopLayout.Format() != DisplayBufferLayout.Rgbx8888() ||
            gopLayout.ByteLength() != 256 ||
            display.Claim(0) != -22 ||
            display.Claim(11) != 0 || display.Owner() != 11 ||
            display.Claim(22) != -16 ||
            display.FillRect(22, 0, 0, 2, 2, 0xFF0000) != -13 ||
            display.FillRect(11, 7, 7, 2, 2, 0xFF0000) != -22 ||
            display.FillRect(11, 0, 0, 2, 2, 0xFF0000) != 0 ||
            displayPixels.Writes() != 4 ||
            displayPixels.Pixel(0) != 0x0000FF ||
            display.SetMode(11, 8, 8) != -95 ||
            display.Release(22) != -13) { return 37; }
        console.WriteByte(65);
        if (serialSink.Writes() != 1 || mirrorSink.Writes() != 0) {
            return 38;
        }
        display.ReleaseOnExit(11);
        console.WriteByte(66);
        if (display.Owner() != 0 || displayPixels.Writes() != 4 ||
            mirrorSink.Writes() < 1 || mirrorSink.Escapes() != 2 ||
            serialSink.Escapes() != 0 ||
            display.FillRect(11, 0, 0, 1, 1, 0) != -13 ||
            display.Claim(22) != 0 || display.Release(22) != 0) {
            return 39;
        }
        MockPixelWriter bgrDisplayPixels = new MockPixelWriter(20480, 64);
        DisplayDevice bgrDisplay = new DisplayDevice(
            new FramebufferMode(20480, 256, 8, 8, 8, 1),
            bgrDisplayPixels, null);
        if (bgrDisplay.Claim(31) != 0 ||
            bgrDisplay.FillRect(31, 0, 0, 1, 1, 0xFF0000) != 0 ||
            bgrDisplayPixels.Pixel(0) != 0xFF0000 ||
            bgrDisplay.Release(31) != 0) { return 40; }
        WindowLayout partialLayout = new WindowLayout(320, 240, 32);
        int partialA = partialLayout.Open(41, 20, 48, 140, 100);
        int partialB = partialLayout.Open(42, 60, 64, 140, 100);
        WindowRenderer partial = new WindowRenderer(partialLayout);
        WindowRenderer reference = new WindowRenderer(partialLayout);
        if (partialA < 1 || partialB < 1 ||
            !partial.Submit(41, partialA, redContent) ||
            !partial.Submit(42, partialB, blueContent) ||
            !reference.Submit(41, partialA, redContent) ||
            !reference.Submit(42, partialB, blueContent) ||
            partial.Compose() == null || reference.Compose() == null ||
            !SameFrame(partial.Compose(), reference.Compose())) { return 41; }
        DamageTracker partialDamage = new DamageTracker(320, 240);
        if (!partialLayout.Move(42, partialB, 100, 80) ||
            !partialDamage.Add(60, 64, 140, 100) ||
            !partialDamage.Add(100, 80, 140, 100) ||
            !SameFrame(partial.ComposeDamage(partialDamage),
                reference.Compose()) ||
            partial.ComposeRegion(-1, 0, 5, 5) != null) { return 42; }
        partialDamage.Clear();
        partial.Hover(118, 96); reference.Hover(118, 96);
        if (!partialDamage.Add(100, 80, 80, 28) ||
            !SameFrame(partial.ComposeDamage(partialDamage),
                reference.Compose())) { return 43; }
        partialDamage.Clear();
        if (!partialLayout.Maximize(42, partialB) ||
            !partialDamage.Add(100, 80, 140, 100) ||
            !partialDamage.Add(0, 32, 320, 208) ||
            !partialDamage.Add(0, 0, 320, 32) ||
            !SameFrame(partial.ComposeDamage(partialDamage),
                reference.Compose())) { return 44; }
        MockPixelWriter framePixels = new MockPixelWriter(24576, 64);
        MockFrameClock frameClock = new MockFrameClock();
        DisplayDevice framed = new DisplayDevice(
            new FramebufferMode(24576, 256, 8, 8, 8, 1),
            framePixels, null);
        framed.AttachFrameClock(frameClock);
        byte[] stats = new byte[20];
        if (framed.Claim(50) != 0 || framed.BeginFrame(51) != -13 ||
            framed.BeginFrame(50) != 0 ||
            framed.FillRect(50, 0, 0, 8, 8, 0x123456) != 0 ||
            framePixels.Writes() != 0 ||
            framed.PresentFrame(51) != -13) { return 45; }
        frameClock.Advance(2500);
        if (framed.PresentFrame(50) != 0 || framePixels.Writes() != 64 ||
            framePixels.Pixel(0) != 0x123456 ||
            framed.PresentFrame(50) != -22 ||
            framed.Stats(51, stats) != -13 ||
            framed.Stats(50, stats) != 20 ||
            stats[0] != 1 || stats[4] != 1 || stats[8] != 0 ||
            stats[12] != 196 || stats[13] != 9) { return 46; }
        if (framed.BeginFrame(50) != 0 ||
            framed.FillRect(50, 1, 1, 2, 2, 0xABCDEF) != 0 ||
            framePixels.Writes() != 64) { return 47; }
        frameClock.Advance(500);
        if (framed.PresentFrame(50) != 0 || framePixels.Writes() != 68 ||
            framePixels.Pixel(9) != 0xABCDEF ||
            framePixels.Pixel(0) != 0x123456 ||
            framed.BeginFrame(50) != 0 ||
            framed.FillRect(50, 3, 3, 1, 1, 0x111111) != 0 ||
            framed.BeginFrame(50) != 0 ||
            framed.FillRect(50, 4, 4, 1, 1, 0x222222) != 0 ||
            framed.PresentFrame(50) != 0 ||
            framePixels.Writes() != 70 ||
            framed.DroppedFrames() != 1 ||
            framed.SubmittedFrames() != 4 ||
            framed.PresentedFrames() != 3 ||
            framed.MaxPresentationMicros() != 2500 ||
            framed.Release(50) != 0) { return 48; }
        MockFrameClock pacingClock = new MockFrameClock();
        MockPixelWriter pacingPixels = new MockPixelWriter(28672, 64);
        DisplayDevice paced = new DisplayDevice(
            new FramebufferMode(28672, 256, 8, 8, 8, 1),
            pacingPixels, null);
        paced.AttachFrameClock(pacingClock);
        if (!paced.SetFramePacing(16) || paced.SetFramePacing(-1) ||
            paced.Claim(60) != 0 || paced.BeginFrame(60) != 0 ||
            paced.FillRect(60, 0, 0, 1, 1, 0x112233) != 0 ||
            paced.PresentFrame(60) != 0 ||
            paced.BeginFrame(60) != -11 ||
            paced.SubmittedFrames() != 1) { return 54; }
        pacingClock.Advance(15000);
        if (paced.BeginFrame(60) != -11) { return 55; }
        pacingClock.Advance(1000);
        if (paced.BeginFrame(60) != 0 ||
            paced.FillRect(60, 1, 1, 1, 1, 0x445566) != 0 ||
            paced.PresentFrame(60) != 0 ||
            paced.PresentedFrames() != 2 ||
            paced.DroppedFrames() != 0 ||
            paced.Release(60) != 0) { return 56; }
        MockNativeDisplayBackend nativeBackend =
            new MockNativeDisplayBackend();
        DisplayDevice nativeDisplay = new DisplayDevice(nativeBackend, null);
        if (!nativeDisplay.Ready() || nativeDisplay.BackendKind() != 2 ||
            nativeDisplay.Width() != 8 || nativeDisplay.Height() != 8 ||
            nativeDisplay.StrideBytes() != 32 ||
            nativeDisplay.ScanoutFormat() != 2 ||
            nativeDisplay.Capabilities() != 7 ||
            nativeDisplay.Claim(70) != 0 ||
            nativeDisplay.BeginFrame(70) != 0 ||
            nativeDisplay.FillRect(70, 2, 2, 1, 1, 0x123456) != 0) {
            return 68;
        }
        nativeBackend.FailNext();
        if (nativeDisplay.PresentFrame(70) != -5 ||
            nativeDisplay.PresentedFrames() != 0 ||
            nativeDisplay.PresentFrame(70) != 0 ||
            nativeBackend.Presentations() != 1 ||
            nativeBackend.LastPixel() != 0x123456 ||
            nativeDisplay.PresentedFrames() != 1) { return 69; }
        nativeDisplay.ShutdownBackend();
        if (nativeDisplay.Ready() || nativeDisplay.Owner() != 0 ||
            nativeDisplay.Claim(71) != -19 ||
            !nativeDisplay.RecoverBackend() ||
            nativeDisplay.Claim(71) != 0 ||
            nativeDisplay.Release(71) != 0) { return 70; }
        if (new DisplayBufferLayout(2048, 2048, 8192, 1).Ready() ||
            new DisplayBufferLayout(8, 8, 31, 1).Ready() ||
            new DisplayBufferLayout(8, 8, 32, 2).Ready() ||
            new DisplayBufferLayout(8, 8, 8388608, 1).Ready() ||
            !new DisplayBufferLayout(8, 8, 64, 1).Ready()) {
            return 71;
        }
        MockNativeDisplayBackend bufferBackend =
            new MockNativeDisplayBackend();
        DisplayDevice buffered = new DisplayDevice(bufferBackend, null);
        if (buffered.Claim(80) != 0 ||
            buffered.AllocateBuffer(81, 8, 8, 32, 1) != -13 ||
            buffered.AllocateBuffer(80, 8, 8, 31, 1) != -22 ||
            buffered.AllocateBuffer(80, 8, 8, 32, 2) != -22 ||
            buffered.AllocateBuffer(80, 7, 8, 28, 1) != -22) {
            return 72;
        }
        int firstBuffer = buffered.AllocateBuffer(80, 8, 8, 32, 1);
        int secondBuffer = buffered.AllocateBuffer(80, 8, 8, 32, 1);
        int thirdBuffer = buffered.AllocateBuffer(80, 8, 8, 32, 1);
        if (firstBuffer < 1 || secondBuffer <= firstBuffer ||
            thirdBuffer <= secondBuffer ||
            buffered.AllocateBuffer(80, 8, 8, 32, 1) != -12 ||
            buffered.BeginBuffer(81, firstBuffer) != -13 ||
            buffered.FillBufferRect(81, firstBuffer, 2, 2, 1, 1,
                0x123456) != -13 ||
            buffered.SubmitBuffer(81, firstBuffer) != -13 ||
            buffered.DestroyBuffer(81, firstBuffer) != -13) { return 73; }
        if (buffered.BeginBuffer(80, firstBuffer) != 0 ||
            buffered.BeginBuffer(80, secondBuffer) != 0 ||
            buffered.FillBufferRect(80, firstBuffer, 2, 2, 1, 1,
                0x123456) != 0 ||
            buffered.FillBufferRect(80, secondBuffer, 2, 2, 1, 1,
                0xABCDEF) != 0) { return 74; }
        int firstFence = buffered.SubmitBuffer(80, firstBuffer);
        if (firstFence < 1 || bufferBackend.LastPixel() != 0x123456 ||
            buffered.BufferCompletion(80, firstBuffer, firstFence) != 1 ||
            buffered.BufferCompletion(81, firstBuffer, firstFence) != -13 ||
            buffered.BufferCompletion(80, firstBuffer, firstFence + 1) != -22 ||
            buffered.FillBufferRect(80, firstBuffer, 0, 0, 1, 1, 0) != -22 ||
            buffered.BeginBuffer(80, firstBuffer) != -16 ||
            buffered.DestroyBuffer(80, firstBuffer) != -16 ||
            buffered.ReleaseBuffer(80, firstBuffer, firstFence + 1) != -22) {
            return 75;
        }
        int secondFence = buffered.SubmitBuffer(80, secondBuffer);
        if (secondFence <= firstFence ||
            bufferBackend.LastPixel() != 0xABCDEF ||
            buffered.ReleaseBuffer(80, firstBuffer, firstFence) != 0 ||
            buffered.ReleaseBuffer(80, firstBuffer, firstFence) != -22 ||
            buffered.ReleaseBuffer(80, secondBuffer, secondFence) != 0 ||
            buffered.DestroyBuffer(80, firstBuffer) != 0) { return 76; }
        int reusedBuffer = buffered.AllocateBuffer(80, 8, 8, 32, 1);
        if (reusedBuffer <= thirdBuffer ||
            buffered.BeginBuffer(80, firstBuffer) != -13 ||
            buffered.BeginBuffer(80, reusedBuffer) != 0 ||
            buffered.BeginBuffer(80, thirdBuffer) != 0 ||
            buffered.FillBufferRect(80, thirdBuffer, 2, 2, 1, 1,
                0x654321) != 0) { return 77; }
        bufferBackend.FailNext();
        if (buffered.SubmitBuffer(80, thirdBuffer) != -5 ||
            buffered.BufferCompletion(80, thirdBuffer, 1) != -22 ||
            buffered.SubmitBuffer(80, thirdBuffer) < 1 ||
            bufferBackend.LastPixel() != 0x654321) { return 78; }
        buffered.ReleaseOnExit(80);
        if (buffered.Owner() != 0 || buffered.Claim(81) != 0 ||
            buffered.BeginBuffer(81, secondBuffer) != -13 ||
            buffered.AllocateBuffer(81, 8, 8, 32, 1) <= reusedBuffer ||
            buffered.Release(81) != 0) { return 79; }
        MockFrameClock bufferClock = new MockFrameClock();
        DisplayDevice pacedBuffer = new DisplayDevice(
            new MockNativeDisplayBackend(), null);
        pacedBuffer.AttachFrameClock(bufferClock);
        if (!pacedBuffer.SetFramePacing(16) ||
            pacedBuffer.Claim(90) != 0) { return 80; }
        int pacedHandle = pacedBuffer.AllocateBuffer(90, 8, 8, 32, 1);
        if (pacedHandle < 1 || pacedBuffer.BeginBuffer(90, pacedHandle) != 0) {
            return 81;
        }
        int pacedFence = pacedBuffer.SubmitBuffer(90, pacedHandle);
        if (pacedFence < 1 ||
            pacedBuffer.ReleaseBuffer(90, pacedHandle, pacedFence) != 0 ||
            pacedBuffer.BeginBuffer(90, pacedHandle) != 0 ||
            pacedBuffer.SubmitBuffer(90, pacedHandle) != -11 ||
            pacedBuffer.BeginFrame(90) != -11) { return 82; }
        bufferClock.Advance(16000);
        if (pacedBuffer.SubmitBuffer(90, pacedHandle) <= pacedFence ||
            pacedBuffer.PresentedFrames() != 2 ||
            pacedBuffer.Release(90) != 0) { return 83; }
        MockVirtioPci pci = new MockVirtioPci();
        pci.Write32(7, 0, 4176 * 65536 + 6900);
        pci.Write32(7, 52, 64);
        pci.Write32(7, 64, 9 + 84 * 256 + 16 * 65536 + 16777216);
        pci.Write32(7, 72, 256); pci.Write32(7, 76, 64);
        pci.Write32(7, 84, 9 + 104 * 256 + 20 * 65536 + 2 * 16777216);
        pci.Write32(7, 92, 512); pci.Write32(7, 96, 64);
        pci.Write32(7, 100, 4);
        pci.Write32(7, 104, 9 + 120 * 256 + 16 * 65536 + 3 * 16777216);
        pci.Write32(7, 112, 768); pci.Write32(7, 116, 1);
        pci.Write32(7, 120, 9 + 16 * 65536 + 4 * 16777216);
        pci.Write32(7, 128, 1024); pci.Write32(7, 132, 16);
        VirtioPciLayout pciLayout = new VirtioPciLayout(pci, 7);
        if (!pciLayout.Ready() || pciLayout.Common().Offset() != 256 ||
            pciLayout.QueueNotifyOffset(3) != 524 ||
            pciLayout.QueueNotifyOffset(16) != -1 ||
            new VirtioPciLayout(pci, 8).Ready()) { return 50; }
        VirtioSplitQueue queue = new VirtioSplitQueue(8);
        if (!queue.Ready() || !queue.Submit(4096, 40, 8192, 24) ||
            queue.Submit(4096, 40, 8192, 24) ||
            queue.Available()[2] != 1 ||
            queue.Descriptors()[12] != 1 ||
            queue.Descriptors()[28] != 2 ||
            queue.Complete(1, 1, 24) ||
            !queue.Complete(1, 0, 24) || queue.Busy() ||
            queue.Completed() != 1 ||
            new VirtioSplitQueue(1).Ready() ||
            new VirtioSplitQueue(6).Ready()) { return 51; }
        MockGpuControl gpuControl = new MockGpuControl(0);
        VirtioGpu2D gpu = new VirtioGpu2D(gpuControl);
        bool invalidCreate = gpu.Create(64, 32, 4096, 1024);
        bool created = gpu.Create(64, 32, 4096, 8192);
        bool scanout = gpu.Scanout(0);
        bool invalidScanout = gpu.Scanout(16);
        bool invalidUpdate = gpu.Update(63, 31, 2, 1);
        bool updated = gpu.Update(3, 4, 16, 8);
        long transferOffset = gpuControl.TransferOffset();
        bool destroyed = gpu.Destroy();
        if (invalidCreate || !created ||
            !scanout || invalidScanout || invalidUpdate || !updated ||
            transferOffset != 1036 || !destroyed || gpu.Current() != null ||
            gpuControl.Count() != 7 ||
            gpuControl.At(0) != 257 || gpuControl.At(1) != 262 ||
            gpuControl.At(2) != 259 || gpuControl.At(3) != 261 ||
            gpuControl.At(4) != 260 || gpuControl.At(5) != 263 ||
            gpuControl.At(6) != 258) { return 52; }
        MockGpuControl failingControl = new MockGpuControl(2);
        VirtioGpu2D failingGpu = new VirtioGpu2D(failingControl);
        if (failingGpu.Create(64, 32, 4096, 8192) ||
            failingGpu.Current() != null || failingControl.Count() != 3 ||
            failingControl.At(2) != 258) { return 53; }
        System.Console.WriteLine("Australis bounded graphics and window layout tests passed");
        return 0;
    }
}
