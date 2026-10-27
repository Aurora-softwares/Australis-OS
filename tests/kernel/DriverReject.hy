public class DriverMain {
    public static int Run(long context) {
        if (context < 4096) { return 2; }
        return 1;
    }
}
