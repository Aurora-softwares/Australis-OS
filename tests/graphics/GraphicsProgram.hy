using Australis.Kernel.Console;
using Australis.Kernel.Graphics;

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

public class Program {
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
        if (!display.Ready() || display.Claim(0) != -22 ||
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
        System.Console.WriteLine("Australis bounded graphics and window layout tests passed");
        return 0;
    }
}
