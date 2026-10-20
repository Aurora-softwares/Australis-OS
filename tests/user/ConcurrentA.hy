public class Program {
    public static int Main(string[] args) {
        int ready = System.Australis.Process.Ready();
        int i = 0;
        while (i < 12) {
            System.Console.WriteLine("concurrent-a");
            int slept = System.Australis.Process.Sleep(1);
            if (slept != 0) { return 2; }
            i = i + 1;
        }
        return 0;
    }
}
