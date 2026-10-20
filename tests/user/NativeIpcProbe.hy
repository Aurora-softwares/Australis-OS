public class Program {
    public static int Main(string[] args) {
        int child = System.Australis.Process.Spawn("/System/Bin/native-ipc.exec");
        if (child < 1) { return 1; }
        int handle = System.Australis.Channel.Open(child, 1);
        if (handle < 1) { return 2; }
        byte[] request = new byte[2]; request[0] = 65; request[1] = 66;
        if (System.Australis.Channel.Send(handle, 1, request) != 0 ||
            System.Australis.Channel.Wait(handle, 5000) != 0) { return 3; }
        byte[] reply = new byte[2];
        if (System.Australis.Channel.Receive(handle, reply) != 2 ||
            reply[0] != 66 || reply[1] != 65) { return 4; }
        byte[] acknowledge = new byte[1]; acknowledge[0] = 1;
        if (System.Australis.Channel.Send(handle, 1, acknowledge) != 0 ||
            System.Australis.Process.Wait(child) != 37 ||
            System.Australis.Channel.Peer(handle) != -1) { return 5; }
        System.Console.WriteLine("native-ipc: passed");
        return 0;
    }
}
