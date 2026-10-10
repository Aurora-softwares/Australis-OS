using Australis.Kernel.Time;
using Australis.Kernel.Events;
using Australis.Kernel.Interrupts;
using Australis.Kernel.Dma;
using Australis.Kernel.Pci;

public class FakeCounter : IMonotonicCounter {
    private long value;
    public FakeCounter(long initial) { value = initial; }
    public long Now() { return value; }
    public void Advance(long amount) { value = value + amount; }
}

public class FakePciConfig : IPciConfigAccess {
    private long command;
    private long low;
    private long high;
    private bool probeLow;
    private bool probeHigh;
    public FakePciConfig() {
        long word = 65536;
        command = 7; low = word * 65215 + 4; high = 0; probeLow = false; probeHigh = false;
    }
    public long Read32(int bdf, int offset) {
        if (offset == 4) { return command; }
        if (offset == 16) { if (probeLow) { long u32 = 65536; return u32 * u32 - 16384; } return low; }
        if (offset == 20) { if (probeHigh) { long u32 = 65536; return u32 * u32 - 1; } return high; }
        return 0;
    }
    public void Write32(int bdf, int offset, long value) {
        if (offset == 4) { command = value; return; }
        if (offset == 16) {
            long u32 = 65536;
            if (value == u32 * u32 - 1) { probeLow = true; }
            else { low = value; probeLow = false; }
            return;
        }
        if (offset == 20) {
            long u32 = 65536;
            if (value == u32 * u32 - 1) { probeHigh = true; }
            else { high = value; probeHigh = false; }
        }
    }
    public long Command() { return command; }
    public void SetHigh(long value) { high = value; }
}

public class Program {
    public static int Main() {
        FakeCounter counter = new FakeCounter(1000);
        DeadlineClock clock = new DeadlineClock(counter, 25);
        long deadline = clock.DeadlineAfter(4);
        if (!clock.IsValid()) { return 11; }
        if (deadline != 1100) { return 12; }
        if (clock.Expired(deadline)) { return 13; }
        counter.Advance(99); if (clock.Expired(deadline)) { return 2; }
        counter.Advance(1); if (!clock.Expired(deadline)) { return 3; }

        DeviceInterruptRegistration registration = new DeviceInterruptRegistration(50);
        int cycle = 0;
        while (cycle < 1024) {
            if (!registration.Register(7) || registration.Register(8) ||
                registration.Unregister(8) || !registration.Unregister(7)) { return 4; }
            cycle = cycle + 1;
        }

        KernelEventLoop events = new KernelEventLoop(4);
        if (!events.Enqueue(7, 11) || !events.Enqueue(7, 12) || !events.Enqueue(7, 13) ||
            !events.Enqueue(7, 14) || events.Enqueue(7, 15) || events.Dropped() != 1) { return 5; }
        long expected = 11;
        while (events.Pending() != 0) {
            if (events.PeekKind() != 7 || events.PeekValue() != expected || !events.CompleteOne()) { return 6; }
            expected = expected + 1;
        }

        DmaAllocator dma = new DmaAllocator(1048576, 48, false);
        if (!dma.Supported() || dma.CapacityPages() != 48) { return 7; }
        cycle = 0;
        while (cycle < 2048) {
            DmaAllocation command = dma.Allocate(2);
            DmaAllocation transfer = dma.Allocate(5);
            if (command == null || transfer == null || command.Address() == transfer.Address() ||
                dma.AllocatedPages() != 7 || !dma.Release(command) || dma.Release(command) ||
                !dma.Release(transfer) || dma.AllocatedPages() != 0) { return 8; }
            cycle = cycle + 1;
        }
        DmaAllocator unsupported = new DmaAllocator(1048576, 8, true);
        if (unsupported.Supported() || unsupported.Allocate(1) != null) { return 9; }

        FakePciConfig config = new FakePciConfig();
        PciBarInfo bar = PciBars.Probe(config, 16, 0);
        if (!bar.IsValid()) { return 101; }
        if (!bar.Is64Bit()) { return 102; }
        long word = 65536;
        if (bar.Address() != word * 65215) { return 103; }
        if (bar.Size() != 16384) { return 104; }
        if (config.Command() != 7) { return 105; }
        config.SetHigh(192);
        bar = PciBars.Probe(config, 16, 0);
        if (!bar.IsValid()) { return 106; }
        long highAddress = 192; highAddress = highAddress * word * word + word * 65215;
        if (bar.Address() != highAddress) { return 107; }
        if (bar.Size() != 16384) { return 108; }

        System.Console.WriteLine("Australis Stage 2 kernel service tests passed");
        return 0;
    }
}
