using SofaTap;

internal static class WindowsLiveTextChecks
{
    public static void Run(Action<bool, string> check)
    {
        check(WindowsTextCoordinates.Normalize("a\r\nb\rc\nd") == "a\nb\nc\nd",
            "live Windows text normalizes CRLF and CR to one canonical LF");
        const string canonical = "A\n中🛋️\nB";
        var plain = WindowsTextCoordinates.ToNativeText(canonical, false);
        var rich = WindowsTextCoordinates.ToNativeText(canonical, true);
        check(plain == "A\r\n中🛋️\r\nB" && rich == "A\r中🛋️\rB",
            "native Edit uses CRLF while RichEdit uses paragraph CR");
        foreach (var offset in Enumerable.Range(0, canonical.Length + 1).Where(offset => WindowsTextCoordinates.Boundary(canonical, offset)))
        {
            check(WindowsTextCoordinates.FromNativeOffset(plain, WindowsTextCoordinates.ToNativeOffset(canonical, offset, false), false) == offset,
                "plain Edit multiline UTF16 selection round trip at " + offset);
            check(WindowsTextCoordinates.FromNativeOffset(plain, WindowsTextCoordinates.ToNativeOffset(canonical, offset, true), true) == offset,
                "RichEdit expanded WM_GETTEXT selection round trip at " + offset);
            check(WindowsTextCoordinates.FromNativeOffset(rich, offset, true) == offset,
                "RichEdit paragraph text selection round trip at " + offset);
        }
        check(WindowsTextCoordinates.FromNativeOffset(plain, 2, false) == -1,
            "plain Edit rejects offsets inside a CRLF pair");
        check(WindowsTextCoordinates.FromNativeOffset(plain, 5, false) == -1 &&
              WindowsTextCoordinates.FromNativeOffset(plain, 4, true) == -1,
            "native selection rejects both surrogate interiors");
        check(!WindowsTextCoordinates.ValidRange(canonical, 0, int.MaxValue) &&
              !WindowsTextCoordinates.ValidRange(canonical, -1, 1) &&
              !WindowsTextCoordinates.ValidRange(canonical, 0, -1),
            "live range validation rejects overflow and negative offsets");
        check(WindowsTextCoordinates.ValidText(canonical, 16000) &&
              WindowsTextCoordinates.ValidText("\t\n", 16000) &&
              !WindowsTextCoordinates.ValidText("\uD800", 16000) &&
              !WindowsTextCoordinates.ValidText("\uDC00", 16000) &&
              !WindowsTextCoordinates.ValidText("a\0b", 16000) &&
              !WindowsTextCoordinates.ValidText("a\rb", 16000) &&
              !WindowsTextCoordinates.ValidText("abc", 2),
            "native live text accepts bounded Unicode and rejects malformed/control text");
        foreach (var (before, after) in new[] {
            ("", "你好"), ("你好", ""), ("abc", "abc"),
            ("前🛋️后", "前🎙️后"), ("A👋B", "A👋👋B"), ("A👋👋B", "A👋B"),
            ("第一行\n第二行", "第一行\n改过\n第二行"), ("稳定片段今天", "稳定片段今天晚上") })
        {
            var diff = WindowsTextCoordinates.Difference(before, after);
            check(before[..diff.Start] + diff.Inserted + before[(diff.Start + diff.Removed)..] == after &&
                  WindowsTextCoordinates.ValidRange(before, diff.Start, diff.Removed) &&
                  WindowsTextCoordinates.ValidText(diff.Inserted, 16000),
                "minimal live edit reconstructs Unicode replacement without splitting surrogate pairs");
        }
        var emoji = WindowsTextCoordinates.Difference("A😀Z", "A😁Z");
        check(emoji == (1, 2, "😁"), "shared emoji high surrogate is included in the changed span");
        var tail = WindowsTextCoordinates.Difference("A𐀀Z", "A𐐀Z");
        check(tail == (1, 2, "𐐀"), "shared emoji low surrogate is included in the changed span");
    }
}
