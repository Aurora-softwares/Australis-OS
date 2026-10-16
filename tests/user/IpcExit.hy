public class Program {
    public static int Main(string[] args) {
        int channel = -1; int retries = 0;
        while (channel < 1 && retries < 100) {
            channel = System.Australis.Channel.Accept(1);
            if (channel < 1) { int slept = System.Australis.Process.Sleep(1); }
            retries = retries + 1;
        }
        if (channel < 1) { return 1; }
        return 0;
    }
}
