public class Program {
    public static int Main(string[] args) {
        int child = System.Australis.Process.Spawn("/System/Bin/ipc-child.exec");
        if (child < 1) { return 1; }
        int channel = System.Australis.Channel.Open(child, 1);
        if (channel < 1 || System.Australis.Channel.Peer(channel) != child) {
            return 2;
        }
        byte[] request = new byte[2]; request[0] = 65; request[1] = 66;
        if (System.Australis.Channel.Send(channel, 1, request) != 0 ||
            System.Australis.Channel.Wait(channel, 5000) != 0) { return 3; }
        byte[] reply = new byte[2];
        if (System.Australis.Channel.Receive(channel, reply) != 2 ||
            reply[0] != 66 || reply[1] != 65) { return 4; }
        byte[] acknowledge = new byte[1]; acknowledge[0] = 1;
        if (System.Australis.Channel.Send(channel, 1, acknowledge) != 0 ||
            System.Australis.Process.Wait(child) != 0 ||
            System.Australis.Channel.Peer(channel) != -1) { return 4; }
        int closing = System.Australis.Process.Spawn("/System/Bin/ipc-noop.exec");
        if (closing < 1) { return 5; }
        int closed = System.Australis.Channel.Open(closing, 1);
        if (closed < 1 || System.Australis.Channel.Close(closed) != 0 ||
            System.Australis.Channel.Peer(closed) != -1 ||
            System.Australis.Process.Wait(closing) != 0) { return 5; }
        int exiting = System.Australis.Process.Spawn("/System/Bin/ipc-exit.exec");
        if (exiting < 1) { return 6; }
        int stale = System.Australis.Channel.Open(exiting, 1);
        if (stale < 1 || System.Australis.Channel.Wait(stale, 5000) != -1 ||
            System.Australis.Process.Wait(exiting) != 0 ||
            System.Australis.Channel.Peer(stale) != -1) { return 7; }
        System.Console.WriteLine("ipc-probe: passed");
        return 0;
    }
}
