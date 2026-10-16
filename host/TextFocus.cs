using System.Diagnostics;

namespace SofaTap;

public enum TextFocusKind { Unknown, Other, Editable, Protected }

// Identity is an ephemeral opaque token, for change detection only. Never a title, value or label.
public readonly record struct TextFocusSnapshot(TextFocusKind Kind, string? Identity = null);

public interface ITextFocusProbe : IDisposable
{
    TextFocusSnapshot Read();
}

public static class TextFocusProbe
{
    public static ITextFocusProbe Create() =>
#if SOFATAP_MAC_APP_STORE
        Unavailable();
#else
        new CachedTextFocusProbe(() =>
        OperatingSystem.IsWindows() ? new WindowsTextFocusProbe() :
        OperatingSystem.IsMacOS() ? new MacTextFocusProbe() :
        OperatingSystem.IsLinux() ? new LinuxTextFocusProbe() : new UnknownTextFocusProbe());
#endif

    public static ITextFocusProbe Unavailable() => new UnknownTextFocusProbe();
}

internal sealed class UnknownTextFocusProbe : ITextFocusProbe
{
    public TextFocusSnapshot Read() => new(TextFocusKind.Unknown);
    public void Dispose() { }
}

// All platform work, including COM initialization, stays on one private background thread.
// A hung accessibility provider cannot block the WebSocket, grow a task queue or keep the
// process alive. At most this one thread remains until the provider returns. Old metadata
// expires rather than leaving a phone keyboard attached to an unknown destination.
internal sealed class CachedTextFocusProbe : ITextFocusProbe
{
    private readonly object _gate = new();
    private readonly ManualResetEventSlim _stop = new();
    private readonly TimeSpan _maxAge;
    private readonly TimeSpan _interval;
    private readonly Func<long> _clock;
    private TextFocusSnapshot _snapshot = new(TextFocusKind.Unknown);
    private long _sampledAt;
    private bool _hasSample;
    private bool _disposed;

    internal CachedTextFocusProbe(Func<ITextFocusProbe> create, TimeSpan? maxAge = null,
        TimeSpan? interval = null, Func<long>? clock = null)
    {
        _maxAge = maxAge ?? TimeSpan.FromMilliseconds(1500);
        _interval = interval ?? TimeSpan.FromMilliseconds(200);
        _clock = clock ?? Stopwatch.GetTimestamp;
        new Thread(() => Poll(create)) { IsBackground = true, Name = "Sofatap text focus" }.Start();
    }

    public TextFocusSnapshot Read()
    {
        lock (_gate)
            return _disposed || !_hasSample || Stopwatch.GetElapsedTime(_sampledAt, _clock()) > _maxAge
                ? new(TextFocusKind.Unknown) : _snapshot;
    }

    private void Poll(Func<ITextFocusProbe> create)
    {
        try
        {
            using var source = create();
            while (!_stop.IsSet)
            {
                var started = _clock();
                TextFocusSnapshot value;
                try { value = source.Read(); }
                catch (Exception) { value = new(TextFocusKind.Unknown); }
                lock (_gate)
                {
                    if (_disposed) break;
                    _snapshot = value; _sampledAt = started; _hasSample = true;
                }
                if (_stop.Wait(_interval)) break;
            }
        }
        catch (Exception) { /* Optional detection failure never prevents manual control. */ }
        finally { _stop.Dispose(); }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            try { _stop.Set(); } catch (ObjectDisposedException) { }
        }
        // Never join a thread that may be blocked inside another application's provider.
    }
}

internal static class TextFocusRules
{
    internal static TextFocusKind Windows(bool? focused, bool? enabled, bool? password,
        bool? valueAvailable, bool? valueReadOnly, bool? textReadOnly)
    {
        if (focused != true) return TextFocusKind.Unknown;
        if (password == true) return TextFocusKind.Protected;
        if (enabled == false) return TextFocusKind.Other;
        if (password != false || enabled != true) return TextFocusKind.Unknown;
        if (valueAvailable == true && valueReadOnly is { } readOnly)
            return readOnly ? TextFocusKind.Other : TextFocusKind.Editable;
        if (textReadOnly is { } textIsReadOnly)
            return textIsReadOnly ? TextFocusKind.Other : TextFocusKind.Editable;
        return valueAvailable == false ? TextFocusKind.Other : TextFocusKind.Unknown;
    }

    internal static TextFocusKind Mac(string? role, string? subrole, bool? enabled, bool? writable)
    {
        if (subrole == "AXSecureTextField" || role == "AXSecureTextField") return TextFocusKind.Protected;
        if (role is null) return TextFocusKind.Unknown;
        if (role is not ("AXTextField" or "AXTextArea" or "AXComboBox")) return TextFocusKind.Other;
        if (enabled == false || writable == false) return TextFocusKind.Other;
        return enabled == true && writable == true ? TextFocusKind.Editable : TextFocusKind.Unknown;
    }
}
