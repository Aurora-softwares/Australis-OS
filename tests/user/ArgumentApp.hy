public class Program {
    public static int Main(string[] args) {
        if (args.Length == 0) {
            System.Console.WriteLine("no-args");
            return 0;
        }
        if (args.Length != 4) { return 10; }
        string path = args[0];
        if (path != "/hello.txt" && path != "/path/with space") { return 11; }
        if (args[1] != "-an") { return 12; }
        if (args[2] != "--argument") { return 13; }
        if (args[3] != "two words" || args[3].Length != 9) { return 14; }
        if (path == "/hello.txt") {
            if (System.Australis.Files.StatKind(path) != 1) { return 15; }
            if (System.Australis.Files.OpenRead(path) != 0) { return 16; }
            if (System.Australis.Files.ReadChecked(16) < 1) { return 17; }
            if (System.Australis.Files.CloseChecked() != 0) { return 18; }
            string root = "/";
            if (System.Australis.Files.DirectoryCount(root) < 1) { return 19; }
        }
        System.Console.WriteLine(args[0]);
        System.Console.WriteLine(args[1]);
        System.Console.WriteLine(args[2]);
        System.Console.WriteLine(args[3]);
        System.Console.WriteLine("arguments-ok");
        return 0;
    }
}
