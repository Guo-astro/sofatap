using System.Diagnostics;
using SofaTap;

internal static class TextFocusChecks
{
    internal static void Run(Action<bool, string> check)
    {
        check(TextFocusRules.Windows(true, true, false, true, false, null) == TextFocusKind.Editable, "UIA writable value is editable");
        check(TextFocusRules.Windows(true, true, false, true, true, false) == TextFocusKind.Other, "UIA value read-only takes precedence over text fallback");
        check(TextFocusRules.Windows(true, true, false, false, null, false) == TextFocusKind.Editable, "UIA text range metadata supports editable documents");
        check(TextFocusRules.Windows(true, true, false, false, null, true) == TextFocusKind.Other, "UIA read-only document is not an editor");
        check(TextFocusRules.Windows(true, true, true, true, false, false) == TextFocusKind.Protected, "UIA password takes precedence over writable metadata");
        check(TextFocusRules.Windows(true, true, null, true, false, null) == TextFocusKind.Unknown, "UIA unknown password flag fails closed");
        check(TextFocusRules.Windows(false, true, false, true, false, null) == TextFocusKind.Unknown, "UIA stale focus fails closed");
        check(TextFocusRules.Windows(true, false, false, true, false, null) == TextFocusKind.Other, "UIA disabled editor does not summon keyboard");
        check(TextFocusRules.Windows(true, true, false, true, null, null) == TextFocusKind.Unknown, "UIA unknown writability fails closed");
        check(TextFocusRules.Mac("AXTextField", "AXSecureTextField", true, true) == TextFocusKind.Protected, "AX secure subrole takes precedence");
        check(TextFocusRules.Mac("AXTextArea", null, true, true) == TextFocusKind.Editable, "AX writable text area is editable");
        check(TextFocusRules.Mac("AXTextField", null, true, false) == TextFocusKind.Other, "AX read-only field does not summon keyboard");
        check(TextFocusRules.Mac("AXSlider", null, true, true) == TextFocusKind.Other, "AX writable non-text value is not an editor");
        check(TextFocusRules.Mac("AXTextField", null, true, null) == TextFocusKind.Unknown, "AX missing writability fails closed");
        check(TextFocusRules.Mac(null, null, true, true) == TextFocusKind.Unknown, "AX missing role fails closed");

        var identity = Guid.NewGuid().ToString("N");
        check(LinuxTextFocusProbe.Parse($"{{\"kind\":\"editable\",\"identity\":\"{identity}\"}}") == new TextFocusSnapshot(TextFocusKind.Editable, identity), "AT-SPI opaque identity accepted");
        check(LinuxTextFocusProbe.Parse("{\"kind\":\"unknown\",\"identity\":null}").Kind == TextFocusKind.Unknown, "AT-SPI absence is unknown");
        foreach (var invalid in new[] {
            "{\"kind\":\"editable\",\"identity\":null}", "{\"kind\":\"editable\",\"identity\":\"a window title\"}",
            "{\"kind\":\"unknown\",\"identity\":null,\"value\":\"private\"}",
            "{\"kind\":\"editable\",\"kind\":\"unknown\",\"identity\":null}",
            "{\"kind\":\"typing\",\"identity\":null}", "[]", new string('x', 129) })
        {
            try { LinuxTextFocusProbe.Parse(invalid); check(false, "invalid focus worker metadata rejected"); }
            catch (Exception error) when (error is IOException or System.Text.Json.JsonException or InvalidOperationException)
            { check(true, "invalid focus worker metadata rejected"); }
        }

        // The provider is deliberately blocked after one valid response. No native API is called.
        using var blocked = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        using var disposed = new ManualResetEventSlim();
        var source = new BlockingProbe(blocked, release, disposed);
        long now = Stopwatch.GetTimestamp();
        using var cache = new CachedTextFocusProbe(() => source, TimeSpan.FromSeconds(1),
            TimeSpan.FromMilliseconds(5), () => Interlocked.Read(ref now));
        check(blocked.Wait(TimeSpan.FromSeconds(2)), "focus provider began stalled second call");
        try
        {
            check(cache.Read().Kind == TextFocusKind.Editable, "cached focus is available without calling stalled provider");
            Interlocked.Add(ref now, Stopwatch.Frequency * 2);
            var watch = Stopwatch.StartNew();
            check(cache.Read().Kind == TextFocusKind.Unknown, "stale focused editor expires to unknown");
            cache.Dispose();
            check(watch.Elapsed < TimeSpan.FromMilliseconds(250), "stalled provider cannot block read or disposal");
            check(cache.Read().Kind == TextFocusKind.Unknown, "disposed cache cannot reveal an old target");
        }
        finally { release.Set(); }
        check(disposed.Wait(TimeSpan.FromSeconds(2)), "provider disposes on its owner thread when it returns");

        using var failed = new CachedTextFocusProbe(() => throw new InvalidOperationException("unavailable"));
        check(failed.Read().Kind == TextFocusKind.Unknown, "optional probe initialization failure is unknown");
    }

    private sealed class BlockingProbe(ManualResetEventSlim blocked, ManualResetEventSlim release, ManualResetEventSlim disposed) : ITextFocusProbe
    {
        private int _calls;
        public TextFocusSnapshot Read()
        {
            if (++_calls > 1) { blocked.Set(); release.Wait(); }
            return new(TextFocusKind.Editable, "test-only-target");
        }
        public void Dispose() => disposed.Set();
    }
}
