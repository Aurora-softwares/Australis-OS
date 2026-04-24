using System;

ClearScreen();
Console.WriteLine("Australis OS booted from C#");

while (true)
{
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
