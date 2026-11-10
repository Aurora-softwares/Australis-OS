public class PortableApiApp {
    public static int Main(string[] args) {
        if (System.Convert.ToInt32("-42") != -42) { return 1; }
        if (System.Convert.ToInt32("-2147483648") != (-2147483647 - 1)) { return 3; }

        System.IO.File.WriteAllText("/data/new", "portable");
        if (!System.IO.File.Exists("/data/new")) { return 2; }

        System.IO.File.WriteAllText("/data/new", "xy");
        System.Console.WriteLine("portable-io");
        return 0;
    }
}
