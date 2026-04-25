using System;

const int LineMax = 160;

ClearScreen();
Console.WriteLine("Australis OS v0.1");
Console.WriteLine("Press keys to echo");
Console.WriteLine("");

char[] line = new char[LineMax];
int linePos = 0;

Console.Write('_');

while (true)
{
    if (!Console.KeyAvailable)
        continue;

    Console.Write('\b');
    Console.Write(' ');
    Console.Write('\b');

    var key = Console.ReadKey(intercept: true);
    int code = (int)key.Key;

    if (code == '\r')
    {
        Console.WriteLine("");
        linePos = 0;
    }
    else if (code == '\b')
    {
        if (linePos > 0)
        {
            linePos--;
            Console.Write('\b');
            Console.Write(' ');
            Console.Write('\b');
        }
    }
    else if (key.Key == ConsoleKey.Escape)
    {
        ClearScreen();
        linePos = 0;
    }
    else if (code >= ' ')
    {
        if (linePos < LineMax)
        {
            line[linePos] = (char)code;
            linePos++;
            Console.Write((char)code);
        }
    }

    Console.Write('_');
}

static void ClearScreen()
{
    for (int row = 0; row < 50; row++)
    {
        Console.SetCursorPosition(0, row);

        for (int column = 0; column < 160; column++)
        {
            Console.Write(' ');
        }
    }

    Console.SetCursorPosition(0, 0);
}
