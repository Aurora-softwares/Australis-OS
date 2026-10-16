public class Program {
    public static int Main(string[] args) {
        System.Console.Write("cwd=");
        System.Console.WriteLine(System.Australis.Process.WorkingDirectory());
        int count = System.Australis.Process.EnvironmentCount();
        int i = 0;
        while (i < count) {
            System.Console.Write("env=");
            System.Console.WriteLine(System.Australis.Process.EnvironmentEntry(i));
            i = i + 1;
        }
        return 0;
    }
}
