public class Program {
    public static int Main(string[] args) {
        int spinner = System.Australis.Process.Spawn("/System/Bin/native-spin.exec");
        int normal = System.Australis.Process.Spawn("/System/Bin/native-pid.exec");
        int faulty = System.Australis.Process.Spawn("/System/Bin/native-fault.exec");
        int context = System.Australis.Process.Spawn("/System/Bin/native-context.exec");
        if (spinner < 1 || normal < 1 || faulty < 1 || context < 1 ||
            spinner == normal || normal == faulty || spinner == faulty) {
            return 1;
        }
        if (System.Australis.Process.Wait(normal) != normal) { return 2; }
        if (System.Australis.Process.Wait(normal) != -4) { return 7; }
        if (System.Australis.Process.Wait(faulty) != -103) { return 3; }
        if (System.Australis.Process.Wait(1) != -4) { return 8; }
        if (System.Australis.Process.Wait(context) != 29) { return 6; }
        if (System.Australis.Process.Terminate(spinner) != 0) { return 4; }
        if (System.Australis.Process.Wait(spinner) != -107) { return 5; }
        System.Console.WriteLine("native-schedule: passed");
        return 23;
    }
}
