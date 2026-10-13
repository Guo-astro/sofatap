using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace SofaTap;

internal static class LiveTextWire
{
    // Native JSON over pinned TLS, never embedded in HTML. Keep Unicode compact,
    // then validate the actual escaped byte budget before reading/writing a field.
    internal static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };
}

// Target is a receiver-local identity. Never put this record directly on the wire.
public sealed record TextEditorSnapshot(string Target, string Text, int SelectionStart, int SelectionLength);

public interface ILiveTextEditor : IDisposable
{
    TextEditorSnapshot Read();
    TextEditorSnapshot Replace(TextEditorSnapshot expected, string text, int selectionStart, int selectionLength);
}

public sealed record LiveTextSnapshot(string Session, int Revision, string Text, int SelectionStart, int SelectionLength);

// One explicit editing session per authenticated connection. Every edit is based
// on an acknowledged snapshot; desktop edits, caret changes and focus switches
// invalidate it instead of attempting to undo or overwrite somebody else's work.
public sealed class LiveTextSession(ILiveTextEditor editor, Func<bool> available) : IDisposable
{
    private TextEditorSnapshot? _snapshot;
    private string? _session;
    private int _revision;

    public LiveTextSnapshot Begin()
    {
        End();
        RequireAvailable();
        var snapshot = editor.Read();
        Validate(snapshot);
        _snapshot = snapshot;
        _session = Guid.NewGuid().ToString("D");
        return Wire();
    }

    public LiveTextSnapshot Sync(string session, int revision, string text, int start, int length)
    {
        if (_session != session || _snapshot is null || revision != _revision + 1)
        {
            End();
            throw new InputInjectionException("live_text_conflict: Editing session or revision changed.");
        }
        try
        {
            RequireAvailable();
            ValidateText(text, start, length);
            var next = editor.Replace(_snapshot, text, start, length);
            Validate(next);
            if (next.Target != _snapshot.Target || next.Text != text || next.SelectionStart != start || next.SelectionLength != length)
                throw new InputInjectionException("live_text_uncertain: The field did not confirm the requested edit.");
            _snapshot = next;
            _revision = revision;
            return Wire();
        }
        catch { End(); throw; }
    }

    public void End(string? session = null)
    {
        if (session is not null && session != _session) return;
        _snapshot = null;
        _session = null;
        _revision = 0;
    }

    private LiveTextSnapshot Wire() => new(_session!, _revision, _snapshot!.Text, _snapshot.SelectionStart, _snapshot.SelectionLength);
    private void RequireAvailable()
    {
        if (!available()) { End(); throw new InputInjectionException("input_unavailable: Desktop input is unavailable."); }
    }
    private static void Validate(TextEditorSnapshot snapshot)
    {
        if (string.IsNullOrEmpty(snapshot.Target)) throw new InputInjectionException("live_text_unsupported: No stable text target.");
        ValidateText(snapshot.Text, snapshot.SelectionStart, snapshot.SelectionLength);
    }
    public static void ValidateText(string text, int start, int length)
    {
        if (text.Length > Protocol.MaximumTextUnits || start < 0 || length < 0 || start > text.Length || length > text.Length - start)
            throw new InputInjectionException("live_text_unsupported: Text or selection exceeds editing limits.");
        for (var i = 0; i < text.Length; i++)
        {
            if (text[i] == '\0') throw new InputInjectionException("live_text_unsupported: NUL text is unsupported.");
            if (char.IsHighSurrogate(text[i]))
            {
                if (++i >= text.Length || !char.IsLowSurrogate(text[i])) throw new InputInjectionException("live_text_unsupported: Invalid Unicode.");
            }
            else if (char.IsLowSurrogate(text[i])) throw new InputInjectionException("live_text_unsupported: Invalid Unicode.");
        }
        if (!Boundary(text, start) || !Boundary(text, start + length))
            throw new InputInjectionException("live_text_unsupported: Selection splits a Unicode character.");
        if (JsonSerializer.SerializeToUtf8Bytes(text, LiveTextWire.Options).Length > Protocol.MaximumFrameBytes - 1024)
            throw new InputInjectionException("live_text_unsupported: Escaped text exceeds the frame limit.");
    }
    private static bool Boundary(string text, int offset) => offset <= 0 || offset >= text.Length ||
        !(char.IsHighSurrogate(text[offset - 1]) && char.IsLowSurrogate(text[offset]));
    public void Dispose() { End(); editor.Dispose(); }
}
