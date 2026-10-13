public class Program {
    private static void PrintArgument(string argument) {
        System.Console.WriteLine(argument);
    }

    public static int Main(string[] args) {
        int index = 0;
        while (index < args.Length) {
            PrintArgument(args[index]);
            index = index + 1;
        }
        return 0;
    }
}
