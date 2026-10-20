using Australis.Kernel.Console;
using Australis.Kernel.Graphics;

public class CountingFrameWriter : IFramebufferPixelWriter {
    private int writes;
    public CountingFrameWriter() { writes = 0; }
    public bool WritePixel(long address, int value) {
        if (address < 4096 || value < 0) { return false; }
        writes = writes + 1; return true;
    }
    public int Writes() { return writes; }
}

public class Program {
    public static int Main(string[] args) {
        if (args.Length != 1) { return 2; }
        PixelSurface surface = new PixelSurface(640, 480);
        if (!surface.Ready() || !surface.Fill(0x112233)) { return 3; }
        int iteration = 0;
        if (args[0] == "draw") {
            while (iteration < 24) {
                if (!surface.FillRect(0, 0, 640, 480, 0x123456) ||
                    !surface.FillRoundedRect(80, 60, 320, 240, 12,
                        0xABCDEF)) { return 4; }
                iteration = iteration + 1;
            }
            if (surface.Pixel(200, 120) != 0xABCDEF) { return 5; }
            return 0;
        }
        if (args[0] == "copy" || args[0] == "alpha") {
            PixelSurface source = new PixelSurface(640, 480);
            if (!source.Ready() || !source.Fill(0xABCDEF)) { return 6; }
            int opacity = 255; int rounds = 24;
            if (args[0] == "alpha") { opacity = 128; rounds = 12; }
            while (iteration < rounds) {
                if (!surface.Blit(source, 0, 0, opacity)) { return 7; }
                iteration = iteration + 1;
            }
            if (surface.Pixel(200, 120) < 0) { return 8; }
            return 0;
        }
        if (args[0] == "compose" || args[0] == "partial") {
            WindowLayout layout = new WindowLayout(640, 480, 32);
            int first = layout.Open(11, 20, 48, 300, 240);
            int second = layout.Open(22, 200, 120, 300, 240);
            PixelSurface firstPixels = new PixelSurface(280, 200);
            PixelSurface secondPixels = new PixelSurface(280, 200);
            if (first < 1 || second < 1 || !firstPixels.Fill(0xCC3322) ||
                !secondPixels.Fill(0x2255CC)) { return 9; }
            WindowRenderer renderer = new WindowRenderer(layout);
            if (!renderer.Submit(11, first, firstPixels) ||
                !renderer.Submit(22, second, secondPixels)) { return 10; }
            int rounds = 12;
            DamageTracker damage = new DamageTracker(640, 480);
            if (args[0] == "partial") {
                if (renderer.Compose() == null ||
                    !damage.Add(230, 150, 64, 64)) { return 11; }
                rounds = 240;
            }
            while (iteration < rounds) {
                PixelSurface frame = null;
                if (args[0] == "partial") {
                    frame = renderer.ComposeDamage(damage);
                } else { frame = renderer.Compose(); }
                if (frame == null) { return 12; }
                iteration = iteration + 1;
            }
            if (renderer.ComposeRegion(230, 150, 1, 1).Pixel(230, 150) < 0) {
                return 13;
            }
            return 0;
        }
        if (args[0] == "present" || args[0] == "present_partial") {
            CountingFrameWriter writer = new CountingFrameWriter();
            FramebufferPresenter presenter = new FramebufferPresenter(
                new FramebufferMode(4096, 640 * 480 * 4, 640, 480,
                    640, 0), writer);
            int rounds = 12; int expected = 640 * 480 * rounds;
            if (args[0] == "present_partial") {
                rounds = 240; expected = 64 * 64 * rounds;
            }
            DamageTracker damage = new DamageTracker(640, 480);
            while (iteration < rounds) {
                if (args[0] == "present_partial") {
                    if (!damage.Add(230, 150, 64, 64) ||
                        !presenter.PresentDamage(surface, damage)) { return 14; }
                } else if (!presenter.Present(surface, 0, 0)) { return 15; }
                iteration = iteration + 1;
            }
            if (writer.Writes() != expected) { return 16; }
            return 0;
        }
        return 17;
    }
}
