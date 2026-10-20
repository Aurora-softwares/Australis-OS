public class PersistentFileApp {
    public static int Main(string[] args) {
        if (System.Australis.Files.StatKind("/data/stage6-done") == 1) {
            if (System.Australis.Files.StatKind("/data/Stage6") != -1 ||
                System.Australis.Files.Status() != 4) { return 20; }
            System.Console.WriteLine("stage6-deletion-recovered");
            return 0;
        }
        if (System.Australis.Files.StatKind("/data/Stage6") == -1) {
            if (System.Australis.Files.Mkdir("/data/Stage6") != 0 ||
                System.Australis.Files.Create("/data/Stage6/value.tmp", "abc") != 0 ||
                System.Australis.Files.OpenWrite("/data/Stage6/value.tmp") != 0 ||
                System.Australis.Files.Append("d") != 0 ||
                System.Australis.Files.Replace("xy") != 0 ||
                System.Australis.Files.Truncate(2) != 0 ||
                System.Australis.Files.CloseChecked() != 0 ||
                System.Australis.Files.Rename("/data/Stage6/value.tmp",
                    "/data/Stage6/value") != 0) { return 1; }
            System.Console.WriteLine("stage6-created");
            return 0;
        }
        if (System.Australis.Files.StatSize("/data/Stage6/value") != 2 ||
            System.Australis.Files.OpenRead("/data/Stage6/value") != 0 ||
            System.Australis.Files.ReadChecked(2) != 2) { return 2; }
        System.Australis.Files.WriteResult();
        System.Console.WriteLine();
        if (System.Australis.Files.CloseChecked() != 0 ||
            System.Australis.Files.Delete("/data/Stage6/value") != 0 ||
            System.Australis.Files.Rmdir("/data/Stage6") != 0 ||
            System.Australis.Files.Create("/data/stage6-done", "yes") != 0) {
            return 3;
        }
        System.Console.WriteLine("stage6-deleted");
        return 0;
    }
}
