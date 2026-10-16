public class Program {
    public static int Main(string[] args) {
        int a = System.Australis.Process.Spawn("/System/Bin/concurrent-a.exec");
        int b = System.Australis.Process.Spawn("/System/Bin/concurrent-b.exec");
        if (a < 1 || b < 1 || a == b) { return 1; }
        int readyA = System.Australis.Process.WaitReady(a, 5000);
        int readyB = System.Australis.Process.WaitReady(b, 5000);
        int resultA = System.Australis.Process.Wait(a);
        int resultB = System.Australis.Process.Wait(b);
        if (readyA != 0 || readyB != 0 || resultA != 0 || resultB != 0) {
            return 2;
        }
        System.Console.WriteLine("concurrent-probe: passed");
        return 0;
    }
}
