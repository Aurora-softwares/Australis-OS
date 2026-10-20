public class Program {
    public static int Main(string[] args) {
        int child = System.Australis.Process.Spawn("/System/Bin/ipc-noop.exec");
        if (child < 1) { return 1; }
        int denied = System.Australis.Channel.Open(child, 1);
        int result = System.Australis.Process.Wait(child);
        if (denied != -2 || result != 0) { return 2; }
        System.Console.WriteLine("ipc-denied: passed");
        return 0;
    }
}
