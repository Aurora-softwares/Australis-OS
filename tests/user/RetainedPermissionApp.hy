
public class Program {
	public static int Main(string[] args) {
		// This program has no display capability.
		// Every privileged operation should return -13.
		System.Console.WriteLine("RP: entered Main");
		int acquire = System.Australis.Display.Acquire();
		int enable = System.Australis.Display.RetainedEnable(30);
		int open = System.Australis.Display.RetainedOpen(20, 48, 140, 100);
		int focus = System.Australis.Display.RetainedFocus(1);
		int move =System.Australis.Display.RetainedMove(1, 25, 52);
		int hover = System.Australis.Display.RetainedHover(10, 10);
		int compose = System.Australis.Display.RetainedComposeRect(0, 0, 8, 8);
		int submit = System.Australis.Display.RetainedSubmitGpu(1, 1);
		int close = System.Australis.Display.RetainedClose(1);
		int minimize = System.Australis.Display.RetainedMinimize(1);
		int restore = System.Australis.Display.RetainedRestore(1);
		System.Console.WriteLine("RP: before maximize");
		int maximize = System.Australis.Display.RetainedMaximize(1);
		System.Console.WriteLine("RP: after maximize");
		System.Console.WriteLine("RP: before unmaximize");
		int unmaximize = System.Australis.Display.RetainedUnmaximize(1);
		System.Console.WriteLine("RP: after unmaximize");
		System.Console.WriteLine("RP: before resize");
		int resize = System.Australis.Display.RetainedResize(1, 160, 110);
		System.Console.WriteLine("RP: after resize");

		if (acquire != -13 || enable != -13 || open != -13 || focus != -13 || move != -13 || hover != -13 || compose != -13 || submit != -13 || close != -13 || minimize != -13 || restore != -13) {
			System.Console.WriteLine("retained-permission: FAILED");
			return 1;
		}

		System.Console.WriteLine("retained-permission: denied");
		return 0;
	}
}
