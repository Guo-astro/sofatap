using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;

namespace SofaTap;

// This deliberately supports known native text controls only. A browser, custom editor,
// password field, elevated process or unavailable desktop is never approximated with keys.
// System messages below WM_USER are marshalled by Windows across process boundaries;
// RichEdit's pointer-bearing EM_EXGETSEL/EM_GETTEXTEX messages are not used here.
[SupportedOSPlatform("windows")]
public sealed class WindowsTextEditor : ILiveTextEditor
{
    private const int MaximumTextUnits = 16_000;
    private const uint GetText = 0x000D, GetTextLength = 0x000E, GetSelection = 0x00B0,
        SetSelection = 0x00B1, ReplaceSelection = 0x00C2, GetPasswordCharacter = 0x00D2;
    private readonly object _gate = new();
    private readonly string _property = "Sofatap.LiveText." + Guid.NewGuid().ToString("N");
    private IntPtr _window, _cookie;
    private string? _identity;
    private bool _disposed;

    public TextEditorSnapshot Read()
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            try { return ReadCore().Snapshot; }
            catch { ForgetTarget(); throw; }
        }
    }

    public TextEditorSnapshot Replace(TextEditorSnapshot expected, string text, int start, int length)
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            if (!WindowsTextCoordinates.ValidText(text, MaximumTextUnits) ||
                !WindowsTextCoordinates.ValidRange(text, start, length))
                throw Failure("live_text_unsupported", "The requested text or selection cannot be synchronized.");
            var mutated = false;
            try
            {
                var current = ReadCore();
                Expect(current.Snapshot, expected);
                if (!current.Target.Multiline && text.Contains('\n'))
                    throw Failure("live_text_unsupported", "This single-line field cannot accept line breaks.");

                if (current.Snapshot.Text != text)
                {
                    // Replace just the changed span, retaining unrelated RichEdit formatting.
                    var change = WindowsTextCoordinates.Difference(expected.Text, text);
                    var replacementSelection = expected with
                    { SelectionStart = change.Start, SelectionLength = change.Removed };
                    Select(current, change.Start, change.Removed);
                    mutated = true; // A selection change also requires confirmed readback.
                    current = ReadCore();
                    Expect(current.Snapshot, replacementSelection);
                    // ReadCore reconfirms the exact foreground control immediately before the
                    // text mutation. No fallback or rollback can write into another control.
                    var replacement = WindowsTextCoordinates.ToNativeText(change.Inserted, current.Target.Rich);
                    Message(current.Target.Window, ReplaceSelection, new IntPtr(1), replacement, true);
                    current = ReadCore();
                    if (current.Snapshot.Target != expected.Target || current.Snapshot.Text != text)
                        throw Failure("live_text_uncertain", "The field changed during input. Check the computer before continuing.");
                }

                if (current.Snapshot.SelectionStart != start || current.Snapshot.SelectionLength != length)
                {
                    // Never apply a late selection to a field that changed after replacement.
                    var confirmed = ReadCore();
                    Expect(confirmed.Snapshot, current.Snapshot);
                    Select(confirmed, start, length);
                    mutated = true;
                }
                var final = ReadCore().Snapshot;
                if (final.Target != expected.Target || final.Text != text ||
                    final.SelectionStart != start || final.SelectionLength != length)
                    throw Failure("live_text_uncertain", "The field did not confirm the requested input. Check the computer before continuing.");
                return final;
            }
            catch (InputInjectionException error) when (mutated && !error.Message.StartsWith("live_text_uncertain:", StringComparison.Ordinal))
            {
                ForgetTarget();
                throw Failure("live_text_uncertain", "Input may have changed the field. Check the computer before continuing.");
            }
            catch { ForgetTarget(); throw; }
        }
    }

    private ReadResult ReadCore()
    {
        var target = FocusedTarget();
        var identity = Identity(target.Window);
        var first = ReadValue(target);
        var second = ReadValue(target);
        var after = FocusedTarget();
        if (target != after || Native.GetProp(target.Window, _property) != _cookie ||
            first != second)
            throw Failure("live_text_changed", "The focused field changed while reading it.");
        return new(target, new(identity, first.Text, first.Start, first.Length));
    }

    private static Value ReadValue(Target target)
    {
        var count = Message(target.Window, GetTextLength, IntPtr.Zero, IntPtr.Zero).ToInt64();
        // WM_GETTEXT expands RichEdit line breaks to CRLF; allow that bounded expansion.
        if (count < 0 || count > MaximumTextUnits * 2)
            throw Failure("live_text_unsupported", "This field is too large for live input.");
        var buffer = new StringBuilder(checked((int)count + 1));
        var copied = Message(target.Window, GetText, new IntPtr(buffer.Capacity), buffer).ToInt64();
        if (copied < 0 || copied > count || copied != buffer.Length)
            throw Failure("live_text_changed", "The field changed while reading its text.");
        var raw = buffer.ToString();
        var canonical = WindowsTextCoordinates.Normalize(raw);
        if (!WindowsTextCoordinates.ValidText(canonical, MaximumTextUnits))
            throw Failure("live_text_unsupported", "This field contains unsupported text.");
        var selection = NativeSelection(target.Window);
        var start = WindowsTextCoordinates.FromNativeOffset(raw, selection.Start, target.Rich);
        var end = WindowsTextCoordinates.FromNativeOffset(raw, selection.End, target.Rich);
        if (start < 0 || end < start || !WindowsTextCoordinates.ValidRange(canonical, start, end - start))
            throw Failure("live_text_unsupported", "The field exposes an unsupported selection.");
        return new(canonical, start, end - start);
    }

    private static void Select(ReadResult current, int start, int length)
    {
        var nativeStart = WindowsTextCoordinates.ToNativeOffset(current.Snapshot.Text, start, current.Target.Rich);
        var nativeEnd = WindowsTextCoordinates.ToNativeOffset(current.Snapshot.Text, start + length, current.Target.Rich);
        Message(current.Target.Window, SetSelection, new IntPtr(nativeStart), new IntPtr(nativeEnd), true);
    }

    private static void Expect(TextEditorSnapshot actual, TextEditorSnapshot expected)
    {
        if (actual.Target != expected.Target)
            throw Failure("live_text_changed", "The focused field changed. Reopen live input for the new field.");
        if (actual != expected)
            throw Failure("live_text_conflict", "The computer's text or selection changed. Reopen live input to continue.");
    }

    private string Identity(IntPtr window)
    {
        if (_window == window && _cookie != IntPtr.Zero && Native.GetProp(window, _property) == _cookie)
            return _identity!;
        ForgetTarget();
        // A private, non-pointer property is deleted automatically when an HWND is destroyed.
        // This prevents a recycled HWND from inheriting an earlier field's live-text identity.
        var cookie = new IntPtr(Random.Shared.Next(1, int.MaxValue));
        if (!Native.SetProp(window, _property, cookie))
            throw Failure("live_text_unsupported", "The field cannot establish a live input session.");
        _window = window; _cookie = cookie; _identity = Guid.NewGuid().ToString("N");
        return _identity;
    }

    private void ForgetTarget()
    {
        if (_window != IntPtr.Zero && Native.GetProp(_window, _property) == _cookie)
            Native.RemoveProp(_window, _property);
        _window = _cookie = IntPtr.Zero; _identity = null;
    }

    private static Target FocusedTarget()
    {
        if (!Environment.UserInteractive || !DefaultInputDesktop())
            throw Failure("live_text_unsupported", "Unlock the computer before using live input.");
        var foreground = Native.GetForegroundWindow();
        if (foreground == IntPtr.Zero) throw Unsupported();
        var thread = Native.GetWindowThreadProcessId(foreground, out var process);
        var info = new Native.GuiThreadInfo { Size = (uint)Marshal.SizeOf<Native.GuiThreadInfo>() };
        if (thread == 0 || !Native.GetGUIThreadInfo(thread, ref info) || info.Focus == IntPtr.Zero ||
            info.Active != foreground || Native.GetAncestor(info.Focus, 2) != foreground ||
            !Native.IsWindowEnabled(info.Focus) || !Native.IsWindowVisible(info.Focus) ||
            !Native.IsWindowUnicode(info.Focus)) throw Unsupported();
        var focusThread = Native.GetWindowThreadProcessId(info.Focus, out var focusProcess);
        if (focusThread != thread || focusProcess != process || process == Environment.ProcessId ||
            !NormalProcess(process)) throw Unsupported();
        var classBuffer = new StringBuilder(256);
        if (Native.GetClassName(info.Focus, classBuffer, classBuffer.Capacity) == 0) throw Unsupported();
        var name = classBuffer.ToString();
        var rich = name.Equals("RichEdit20W", StringComparison.OrdinalIgnoreCase) ||
            name.Equals("RICHEDIT50W", StringComparison.OrdinalIgnoreCase) ||
            name.StartsWith("WindowsForms10.RichEdit20W.", StringComparison.OrdinalIgnoreCase) ||
            name.StartsWith("WindowsForms10.RichEdit50W.", StringComparison.OrdinalIgnoreCase);
        var plain = name.Equals("Edit", StringComparison.OrdinalIgnoreCase) ||
            name.StartsWith("WindowsForms10.EDIT.", StringComparison.OrdinalIgnoreCase);
        if (!rich && !plain) throw Unsupported();
        var style = Native.GetWindowLong(info.Focus, -16);
        if ((style & (0x20 | 0x800)) != 0 ||
            Message(info.Focus, GetPasswordCharacter, IntPtr.Zero, IntPtr.Zero) != IntPtr.Zero)
            throw Unsupported();
        return new(info.Focus, foreground, process, thread, rich, (style & 0x4) != 0);
    }

    private static bool DefaultInputDesktop()
    {
        var desktop = Native.OpenInputDesktop(0, false, 0x0001);
        if (desktop == IntPtr.Zero) return false;
        try
        {
            return DesktopName(desktop) == "Default" &&
                DesktopName(Native.GetThreadDesktop(Native.GetCurrentThreadId())) == "Default";
        }
        finally { Native.CloseDesktop(desktop); }
    }

    private static string? DesktopName(IntPtr desktop)
    {
        var name = new StringBuilder(128);
        return desktop != IntPtr.Zero && Native.GetUserObjectInformation(desktop, 2, name, (uint)(name.Capacity * 2), out _)
            ? name.ToString() : null;
    }

    private static bool NormalProcess(uint process)
    {
        if (!Native.ProcessIdToSessionId(process, out var session) ||
            !Native.ProcessIdToSessionId((uint)Environment.ProcessId, out var ownSession) || session != ownSession)
            return false;
        var handle = Native.OpenProcess(0x1000, false, process);
        if (handle == IntPtr.Zero) return false;
        try
        {
            if (!Native.OpenProcessToken(handle, 0x0008, out var token)) return false;
            try
            {
                var elevation = Marshal.AllocHGlobal(4);
                try
                {
                    if (!Native.GetTokenInformation(token, 20, elevation, 4, out _) || Marshal.ReadInt32(elevation) != 0)
                        return false;
                }
                finally { Marshal.FreeHGlobal(elevation); }
                Native.GetTokenInformation(token, 25, IntPtr.Zero, 0, out var needed);
                if (needed == 0 || needed > 4096) return false;
                var label = Marshal.AllocHGlobal((int)needed);
                try
                {
                    if (!Native.GetTokenInformation(token, 25, label, needed, out _)) return false;
                    var sid = Marshal.ReadIntPtr(label);
                    if (!Native.IsValidSid(sid)) return false;
                    var count = Marshal.ReadByte(Native.GetSidSubAuthorityCount(sid));
                    if (count == 0) return false;
                    var integrity = Marshal.ReadInt32(Native.GetSidSubAuthority(sid, (uint)(count - 1)));
                    return integrity is >= 0x1000 and <= 0x2000;
                }
                finally { Marshal.FreeHGlobal(label); }
            }
            finally { Native.CloseHandle(token); }
        }
        finally { Native.CloseHandle(handle); }
    }

    private static (int Start, int End) NativeSelection(IntPtr window)
    {
        // EM_GETSEL is a system message: Windows marshals these two DWORD pointers.
        var start = Marshal.AllocHGlobal(4); var end = Marshal.AllocHGlobal(4);
        try
        {
            Marshal.WriteInt32(start, -1); Marshal.WriteInt32(end, -1);
            Message(window, GetSelection, start, end);
            return (Marshal.ReadInt32(start), Marshal.ReadInt32(end));
        }
        finally { Marshal.FreeHGlobal(start); Marshal.FreeHGlobal(end); }
    }

    private static IntPtr Message(IntPtr window, uint message, IntPtr first, IntPtr second, bool mutation = false)
    {
        if (Native.SendMessageTimeout(window, message, first, second, 0x23, 150, out var result) == IntPtr.Zero)
            throw MessageFailure(mutation);
        return result;
    }
    private static IntPtr Message(IntPtr window, uint message, IntPtr first, StringBuilder second)
    {
        if (Native.SendMessageTimeout(window, message, first, second, 0x23, 150, out var result) == IntPtr.Zero)
            throw MessageFailure(false);
        return result;
    }
    private static IntPtr Message(IntPtr window, uint message, IntPtr first, string second, bool mutation)
    {
        if (Native.SendMessageTimeout(window, message, first, second, 0x23, 150, out var result) == IntPtr.Zero)
            throw MessageFailure(mutation);
        return result;
    }
    private static InputInjectionException MessageFailure(bool mutation) => mutation
        ? Failure("live_text_uncertain", "The field did not confirm input in time. Check the computer before continuing.")
        : Failure("live_text_unsupported", "The field did not respond in time.");
    private static InputInjectionException Unsupported() => Failure("live_text_unsupported", "Focus a normal native text field to use live input.");
    private static InputInjectionException Failure(string code, string description) => new($"{code}: {description}");
    private void ThrowIfDisposed()
    {
        if (_disposed) throw Failure("live_text_unsupported", "The live input session is closed.");
    }
    public void Dispose()
    {
        lock (_gate) { if (_disposed) return; ForgetTarget(); _disposed = true; }
    }

    private readonly record struct Target(IntPtr Window, IntPtr Foreground, uint Process, uint Thread, bool Rich, bool Multiline);
    private readonly record struct Value(string Text, int Start, int Length);
    private readonly record struct ReadResult(Target Target, TextEditorSnapshot Snapshot);
    private static class Native
    {
        [StructLayout(LayoutKind.Sequential)] internal struct Rect { internal int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] internal struct GuiThreadInfo
        {
            internal uint Size, Flags;
            internal IntPtr Active, Focus, Capture, MenuOwner, MoveSize, Caret;
            internal Rect CaretRect;
        }
        [DllImport("user32.dll")] internal static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool GetGUIThreadInfo(uint thread, ref GuiThreadInfo info);
        [DllImport("user32.dll")] internal static extern IntPtr GetAncestor(IntPtr window, uint flags);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool IsWindowEnabled(IntPtr window);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool IsWindowVisible(IntPtr window);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool IsWindowUnicode(IntPtr window);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] internal static extern int GetWindowLong(IntPtr window, int index);
        [DllImport("user32.dll", EntryPoint = "GetClassNameW", CharSet = CharSet.Unicode)] internal static extern int GetClassName(IntPtr window, StringBuilder name, int count);
        [DllImport("user32.dll", EntryPoint = "GetPropW", CharSet = CharSet.Unicode)] internal static extern IntPtr GetProp(IntPtr window, string name);
        [DllImport("user32.dll", EntryPoint = "SetPropW", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool SetProp(IntPtr window, string name, IntPtr value);
        [DllImport("user32.dll", EntryPoint = "RemovePropW", CharSet = CharSet.Unicode)] internal static extern IntPtr RemoveProp(IntPtr window, string name);
        [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode)] internal static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr first, IntPtr second, uint flags, uint timeout, out IntPtr result);
        [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode)] internal static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr first, StringBuilder second, uint flags, uint timeout, out IntPtr result);
        [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode)] internal static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr first, string second, uint flags, uint timeout, out IntPtr result);
        [DllImport("user32.dll")] internal static extern IntPtr OpenInputDesktop(uint flags, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint access);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseDesktop(IntPtr desktop);
        [DllImport("user32.dll")] internal static extern IntPtr GetThreadDesktop(uint thread);
        [DllImport("user32.dll", EntryPoint = "GetUserObjectInformationW", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool GetUserObjectInformation(IntPtr obj, int index, StringBuilder value, uint size, out uint needed);
        [DllImport("kernel32.dll")] internal static extern uint GetCurrentThreadId();
        [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool ProcessIdToSessionId(uint process, out uint session);
        [DllImport("kernel32.dll")] internal static extern IntPtr OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint process);
        [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseHandle(IntPtr handle);
        [DllImport("advapi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool GetTokenInformation(IntPtr token, int kind, IntPtr value, uint size, out uint needed);
        [DllImport("advapi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool IsValidSid(IntPtr sid);
        [DllImport("advapi32.dll")] internal static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
        [DllImport("advapi32.dll")] internal static extern IntPtr GetSidSubAuthority(IntPtr sid, uint index);
    }
}

// Pure coordinate logic is platform independent and covered without injecting real input.
internal static class WindowsTextCoordinates
{
    internal static string Normalize(string value) => value.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
    internal static string ToNativeText(string value, bool rich) => value.Replace("\n", rich ? "\r" : "\r\n", StringComparison.Ordinal);
    internal static bool ValidText(string text, int maximum)
    {
        if (text.Length > maximum || text.Contains('\r')) return false;
        for (var i = 0; i < text.Length; i++)
        {
            var value = text[i];
            if (char.IsControl(value) && value is not ('\n' or '\t')) return false;
            if (char.IsHighSurrogate(value))
            { if (++i >= text.Length || !char.IsLowSurrogate(text[i])) return false; }
            else if (char.IsLowSurrogate(value)) return false;
        }
        return true;
    }
    internal static bool Boundary(string text, int offset) => offset >= 0 && offset <= text.Length &&
        (offset == 0 || offset == text.Length || !char.IsHighSurrogate(text[offset - 1]) || !char.IsLowSurrogate(text[offset]));
    internal static bool ValidRange(string text, int start, int length) => start >= 0 && length >= 0 &&
        start <= text.Length && length <= text.Length - start && Boundary(text, start) && Boundary(text, start + length);
    internal static int FromNativeOffset(string raw, int offset, bool rich)
    {
        if (offset < 0) return -1;
        var canonical = Normalize(raw);
        if (rich) return Boundary(canonical, offset) ? offset : -1;
        if (offset > raw.Length || !Boundary(raw, offset)) return -1;
        // An offset between CR and LF is not a canonical character boundary.
        if (offset > 0 && offset < raw.Length && raw[offset - 1] == '\r' && raw[offset] == '\n') return -1;
        return Normalize(raw[..offset]).Length;
    }
    internal static int ToNativeOffset(string canonical, int offset, bool rich) => rich ? offset :
        offset + canonical.AsSpan(0, offset).Count('\n');
    internal static (int Start, int Removed, string Inserted) Difference(string previous, string current)
    {
        var prefix = 0;
        while (prefix < previous.Length && prefix < current.Length && previous[prefix] == current[prefix]) prefix++;
        while (!Boundary(previous, prefix) || !Boundary(current, prefix)) prefix--;
        var suffix = 0;
        while (suffix < previous.Length - prefix && suffix < current.Length - prefix &&
            previous[previous.Length - suffix - 1] == current[current.Length - suffix - 1]) suffix++;
        while (!Boundary(previous, previous.Length - suffix) || !Boundary(current, current.Length - suffix)) suffix--;
        return (prefix, previous.Length - prefix - suffix, current.Substring(prefix, current.Length - prefix - suffix));
    }
}
