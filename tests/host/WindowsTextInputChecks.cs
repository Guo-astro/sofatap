using SofaTap;

internal static class WindowsTextInputChecks
{
    // Inspect the same native INPUT arrays that Apply submits, without calling user32.
    public static void Run(Action<bool, string> check)
    {
        const uint Keyboard = 1, Up = 2, Unicode = 4;
        const ushort Return = 0x0D;
        (uint Type, ushort Key, ushort Scan, uint Flags)[] Snapshot(WindowsInput.Native.Input[] events) =>
            events.Select(item => (item.Type, item.Union.Keyboard.VirtualKey,
                item.Union.Keyboard.Scan, item.Union.Keyboard.Flags)).ToArray();
        var returnPair = new (uint, ushort, ushort, uint)[]
        {
            (Keyboard, Return, 0, 0), (Keyboard, Return, 0, Up)
        };
        foreach (var newline in new[] { "\n", "\r", "\r\n" })
            check(Snapshot(WindowsInput.BuildTextEvents(newline)).SequenceEqual(returnPair),
                "Windows LF, CR and CRLF each produce exactly one virtual Return pair");

        var mixed = WindowsInput.BuildTextEvents("A\nB\r\nC\rD");
        check(Snapshot(mixed).SequenceEqual(new (uint, ushort, ushort, uint)[]
        {
            (Keyboard, 0, 'A', Unicode), (Keyboard, 0, 'A', Unicode | Up),
            (Keyboard, Return, 0, 0), (Keyboard, Return, 0, Up),
            (Keyboard, 0, 'B', Unicode), (Keyboard, 0, 'B', Unicode | Up),
            (Keyboard, Return, 0, 0), (Keyboard, Return, 0, Up),
            (Keyboard, 0, 'C', Unicode), (Keyboard, 0, 'C', Unicode | Up),
            (Keyboard, Return, 0, 0), (Keyboard, Return, 0, Up),
            (Keyboard, 0, 'D', Unicode), (Keyboard, 0, 'D', Unicode | Up)
        }), "Windows mixed newlines preserve text order without a trailing Enter or Unicode CR packet");
        check(Snapshot(WindowsInput.BuildTextEvents("\n\n")).SequenceEqual(returnPair.Concat(returnPair)),
            "Windows preserves explicitly requested empty lines");
        check(WindowsInput.BuildTextEvents("").Length == 0, "Windows empty text creates no key events");

        var unicode = WindowsInput.BuildTextEvents("中🛋️");
        ushort[] codeUnits = [0x4E2D, 0xD83D, 0xDECB, 0xFE0F];
        check(Snapshot(unicode).SequenceEqual(codeUnits.SelectMany(unit => new[]
        {
            (Keyboard, (ushort)0, unit, Unicode), (Keyboard, (ushort)0, unit, Unicode | Up)
        })), "Windows Chinese, surrogate pair and variation selector remain Unicode key pairs with no Enter");

        var interrupted = WindowsInput.BuildTextEvents("A\nB");
        check(WindowsInput.BuildFailureReleases(interrupted, 0, []).Length == 0,
            "Windows zero-event text failure releases no key");
        check(Snapshot(WindowsInput.BuildFailureReleases(interrupted, 3, []))
                .SequenceEqual(new[] { returnPair[1] }),
            "Windows partial text ending at Return down releases only that Return");
        check(WindowsInput.BuildFailureReleases(interrupted, 4, []).Length == 0,
            "Windows text failure after Return up does not release completed keys");
        check(Snapshot(WindowsInput.BuildFailureReleases(interrupted, 5, []))
                .SequenceEqual(new[] { (Keyboard, (ushort)0, (ushort)'B', Unicode | Up) }),
            "Windows partial Unicode after a newline retains normal Unicode release cleanup");
    }
}
