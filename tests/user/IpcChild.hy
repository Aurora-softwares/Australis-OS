public class Program {
    public static int Main(string[] args) {
        int channel = -1; int retries = 0;
        while (channel < 1 && retries < 100) {
            channel = System.Australis.Channel.Accept(1);
            if (channel < 1) { int slept = System.Australis.Process.Sleep(1); }
            retries = retries + 1;
        }
        if (channel < 1 || System.Australis.Channel.Wait(channel, 5000) != 0) {
            return 1;
        }
        byte[] request = new byte[2];
        if (System.Australis.Channel.Receive(channel, request) != 2 ||
            request[0] != 65 || request[1] != 66) { return 2; }
        byte[] reply = new byte[2]; reply[0] = 66; reply[1] = 65;
        if (System.Australis.Channel.Send(channel, 1, reply) != 0) { return 3; }
        // Let the blocked parent resume and send its acknowledgment before
        // this child enters another channel wait in the cooperative runtime.
        System.Australis.Process.Sleep(20);
        if (System.Australis.Channel.Wait(channel, 5000) != 0) { return 4; }
        byte[] acknowledge = new byte[1];
        if (System.Australis.Channel.Receive(channel, acknowledge) != 1 ||
            acknowledge[0] != 1) { return 5; }
        return 0;
    }
}
