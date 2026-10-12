public class FileApiApp {
    public static int Main(string[] args) {
        if (System.Australis.Files.ApiVersion() != 1) { return 18; }
        if (System.Australis.Files.OpenRead("/hello.txt") != 0) { return 19; }
        if (System.Australis.Files.ReadChecked(5) != 5 ||
            System.Australis.Files.ResultByte(0) != 104 ||
            System.Australis.Files.ResultByte(4) != 111 ||
            System.Australis.Files.ResultU32(0) <= 0) { return 20; }
        if (System.Australis.Files.ResultByte(5) != -1 ||
            System.Australis.Files.Status() != 1 ||
            System.Australis.Files.CloseChecked() != 0) { return 21; }
        if (System.Australis.Files.OpenRead("/hello.txt") != 0 ||
            System.Australis.Files.ReadChecked(4) != 4 ||
            System.Australis.Files.ResultU32(0) <= 2147483647 ||
            System.Australis.Files.CloseChecked() != 0) { return 23; }
        if (System.Australis.Files.DirectoryName("/", 1) != -1 ||
            System.Australis.Files.Status() != 5) { return 22; }
        if (System.Australis.Files.Create("/data/new", "abc") != 0) { return 1; }
        if (System.Australis.Files.StatKind("/data/new") != 1) { return 2; }
        if (System.Australis.Files.StatSize("/data/new") != 3) { return 3; }
        if (System.Australis.Files.OpenWrite("/data/new") != 0) { return 4; }
        if (System.Australis.Files.Append("d") != 0) { return 5; }
        if (System.Australis.Files.Replace("xy") != 0) { return 6; }
        if (System.Australis.Files.Truncate(2) != 0) { return 7; }
        if (System.Australis.Files.CloseChecked() != 0) { return 8; }
        if (System.Australis.Files.StatSize("/data/new") != 2) { return 9; }
        if (System.Australis.Files.Mkdir("/data/folder") != 8) { return 10; }
        if (System.Australis.Files.Rmdir("/data/folder") != 8) { return 11; }
        if (System.Australis.Files.Rename("/data/new", "/data/renamed") != 8) {
            return 12;
        }
        if (System.Australis.Files.Delete("/data/new") != 0) { return 13; }
        if (System.Australis.Files.Status() != 0) { return 14; }
        if (System.Australis.Files.StatSize("/missing") != -1 ||
            System.Australis.Files.Status() != 4) { return 15; }
        if (System.Australis.Files.DirectoryCount("/missing") != -1 ||
            System.Australis.Files.Status() != 4) { return 16; }
        if (System.Australis.Files.OpenWrite("/missing") != 4 ||
            System.Australis.Files.Status() != 4) { return 17; }
        return 0;
    }
}
