
public class Program {
    public static int Main(string[] args) {
        // This program must NOT have display capability.
        // Every privileged operation must return EACCES (-13).

        int acquire =
            System.Australis.Display.Acquire();

        int enable =
            System.Australis.Display.RetainedEnable(30);

        int open =
            System.Australis.Display.RetainedOpen(
                20, 48, 140, 100);

        if (acquire != -13 ||
            enable != -13 ||
            open != -13) {

            System.Console.WriteLine(
                "retained-permission: FAILED");
            return 1;
        }

        System.Console.WriteLine(
            "retained-permission: denied");
        return 0;
    }
}
