public class Program {
    private static int Increase(int value) { return value + 1; }
    private static int Score(int value) { return Increase(value) + 1; }
    private static string Pass(string value) { return value; }

    public static int Main(string[] args) {
        if (args.Length != 3 || args[0] != "/hello.txt" ||
            args[1] != "-an" || args[2] != "two words") { return 31; }
        if (Score(21) != 23 || Pass(args[2]).Length != 9) { return 32; }
        byte[] bytes = new byte[3];
        bytes[0] = 65; bytes[1] = 66; bytes[2] = 67;
        if (bytes.Length != 3 || bytes[0] != 65 || bytes[2] != 67) { return 33; }
        if (System.Australis.SystemInfo.Query(0) != 1 ||
            System.Australis.SystemInfo.Query(1) != 1 ||
            System.Australis.SystemInfo.Query(3) < 1) { return 34; }
        System.Console.WriteLine(args[0]);
        System.Console.WriteLine(args[1]);
        System.Console.WriteLine(Pass(args[2]));
        System.Console.WriteLine("stage1-ok");
        return 23;
    }
}
