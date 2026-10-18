public class Program {
    public static int Main(string[] args) {
        int child = System.Australis.Process.Spawn("/System/Bin/native-spin.exec");
        if (child < 1) { return 1; }
        return 31;
    }
}
