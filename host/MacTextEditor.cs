using System.Runtime.InteropServices;

namespace SofaTap;

// Used only by an explicit live-text session with serialized operations. This does
// not monitor documents, use the clipboard, or send global keyboard events.
internal sealed class MacTextEditor : ILiveTextEditor
{
    private readonly IMacTextEditorAccess _access;
    private IntPtr _target;
    private string? _identity;
    private bool _disposed;

    internal MacTextEditor() : this(new MacTextEditorAccess()) { }
    internal MacTextEditor(IMacTextEditorAccess access) => _access = access;

    public TextEditorSnapshot Read()
    {
        if (_disposed || !_access.Trusted)
        {
            ForgetTarget();
            throw Error("live_text_unsupported", "Mac accessibility access is unavailable.");
        }
        var focused = _access.Focused();
        if (focused == IntPtr.Zero) { ForgetTarget(); throw Error("live_text_unsupported", "No supported editor is focused."); }
        try
        {
            var value = _access.Read(focused);
            Validate(value.Text, value.Start, value.Length);
            // Text/selection and focus are separate AX requests. Reject a torn
            // snapshot rather than treating an old field as the current one.
            if (_access.Read(focused) != value || !IsFocused(focused))
                throw Error("live_text_changed", "The focused editor changed while it was inspected.");
            if (_target == IntPtr.Zero || !_access.Equal(_target, focused))
            {
                ForgetTarget();
                _target = focused;
                focused = IntPtr.Zero; // Keep this owned AX reference for the session identity.
                _identity = Guid.NewGuid().ToString("N");
            }
            return new(_identity!, value.Text, value.Start, value.Length);
        }
        catch { ForgetTarget(); throw; }
        finally { if (focused != IntPtr.Zero) _access.Release(focused); }
    }

    public TextEditorSnapshot Replace(TextEditorSnapshot expected, string text, int selectionStart, int selectionLength)
    {
        Validate(text, selectionStart, selectionLength);
        var current = Read();
        if (current.Target != expected.Target)
            throw Error("live_text_changed", "The focused editor is no longer the live-text target.");
        if (current != expected)
            throw Error("live_text_conflict", "The text or selection was changed outside this live-text session.");
        if (current.Text == text && current.SelectionStart == selectionStart && current.SelectionLength == selectionLength)
            return current;
        if (!IsFocused(_target))
            throw Error("live_text_changed", "Focus changed before the edit.");

        // AX has no atomic compare-and-swap. Never retry or roll back a failed
        // write: the target may already have accepted it or received user edits.
        try
        {
            if (current.Text != text)
            {
                var change = Difference(current.Text, text);
                _access.SetSelection(_target, change.Start, change.Removed);
                var selected = Read();
                if (selected != current with { SelectionStart = change.Start, SelectionLength = change.Removed })
                    throw Error("live_text_uncertain", "The editor changed while preparing the replacement.");
                // AXSelectedText changes only the selected span. Setting AXValue
                // would rewrite the entire field and can discard rich formatting.
                _access.ReplaceSelection(_target, change.Inserted);
                current = Read();
                if (current.Target != expected.Target || current.Text != text)
                    throw Error("live_text_uncertain", "The editor did not confirm the replacement.");
            }
            if (current.SelectionStart != selectionStart || current.SelectionLength != selectionLength)
            {
                if (Read() != current)
                    throw Error("live_text_uncertain", "The editor changed before restoring the selection.");
                _access.SetSelection(_target, selectionStart, selectionLength);
            }
        }
        catch
        {
            ForgetTarget();
            throw Error("live_text_uncertain", "The editor may have accepted part of the update. Do not replay it automatically.");
        }

        TextEditorSnapshot result;
        try { result = Read(); }
        catch
        {
            ForgetTarget();
            throw Error("live_text_uncertain", "The editor did not confirm the update. Do not replay it automatically.");
        }
        if (result.Target != expected.Target || result.Text != text ||
            result.SelectionStart != selectionStart || result.SelectionLength != selectionLength)
        {
            ForgetTarget();
            throw Error("live_text_changed", "The editor changed the submitted text or selection; start a new live-text session.");
        }
        return result;
    }

    private bool IsFocused(IntPtr element)
    {
        var focused = _access.Focused();
        try { return focused != IntPtr.Zero && _access.Equal(element, focused); }
        finally { if (focused != IntPtr.Zero) _access.Release(focused); }
    }

    internal static void Validate(string text, int start, int length)
    {
        if (text.Length > Protocol.MaximumTextUnits || start < 0 || length < 0 || start > text.Length || length > text.Length - start)
            throw Error("live_text_unsupported", "The editor text or selection is outside the supported range.");
        for (var index = 0; index < text.Length; index++)
        {
            if (text[index] == '\0') throw Error("live_text_unsupported", "The editor contains unsupported text.");
            if (char.IsHighSurrogate(text[index]))
            {
                if (++index >= text.Length || !char.IsLowSurrogate(text[index]))
                    throw Error("live_text_unsupported", "The editor contains invalid Unicode.");
            }
            else if (char.IsLowSurrogate(text[index])) throw Error("live_text_unsupported", "The editor contains invalid Unicode.");
        }
        if ((start > 0 && start < text.Length && char.IsLowSurrogate(text[start])) ||
            (start + length > 0 && start + length < text.Length && char.IsLowSurrogate(text[start + length])))
            throw Error("live_text_unsupported", "The selection splits a Unicode character.");
    }

    private static (int Start, int Removed, string Inserted) Difference(string previous, string current)
    {
        static bool Boundary(string value, int index) => index == 0 || index == value.Length ||
            !char.IsHighSurrogate(value[index - 1]) || !char.IsLowSurrogate(value[index]);
        var prefix = 0;
        while (prefix < previous.Length && prefix < current.Length && previous[prefix] == current[prefix]) prefix++;
        while (!Boundary(previous, prefix) || !Boundary(current, prefix)) prefix--;
        var suffix = 0;
        while (suffix < previous.Length - prefix && suffix < current.Length - prefix &&
               previous[previous.Length - suffix - 1] == current[current.Length - suffix - 1]) suffix++;
        while (!Boundary(previous, previous.Length - suffix) || !Boundary(current, current.Length - suffix)) suffix--;
        return (prefix, previous.Length - prefix - suffix, current.Substring(prefix, current.Length - prefix - suffix));
    }

    private void ForgetTarget()
    {
        if (_target != IntPtr.Zero) _access.Release(_target);
        _target = IntPtr.Zero;
        _identity = null;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        ForgetTarget();
        _access.Dispose();
    }

    internal static InputInjectionException Error(string code, string detail) => new($"{code}: {detail}");
}

internal readonly record struct MacEditorValue(string Text, int Start, int Length);

// Narrow native boundary also allows conflict/error handling to be checked
// without opening windows or granting accessibility access in a test run.
internal interface IMacTextEditorAccess : IDisposable
{
    bool Trusted { get; }
    IntPtr Focused(); // An owned reference, including when it denotes the same target.
    bool Equal(IntPtr first, IntPtr second);
    void Release(IntPtr element);
    MacEditorValue Read(IntPtr element);
    void ReplaceSelection(IntPtr element, string text);
    void SetSelection(IntPtr element, int start, int length);
}

internal sealed class MacTextEditorAccess : IMacTextEditorAccess
{
    private const string AX = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices";
    private const string CF = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    private const uint RangeType = 4; // kAXValueCFRangeType
    private readonly Dictionary<string, IntPtr> _attributes = new();
    private readonly IntPtr _system;
    private bool _disposed;

    internal MacTextEditorAccess()
    {
        if (!OperatingSystem.IsMacOS()) return;
        _system = AXUIElementCreateSystemWide();
        foreach (var name in new[] { "AXFocusedUIElement", "AXRole", "AXSubrole", "AXEnabled", "AXValue", "AXSelectedTextRange", "AXSelectedText" })
            _attributes[name] = CFStringCreateWithCharacters(IntPtr.Zero, Units(name), name.Length);
    }

    public bool Trusted => !_disposed && _system != IntPtr.Zero && AXIsProcessTrusted();
    public IntPtr Focused() => Trusted ? Copy(_system, "AXFocusedUIElement", required: false) : IntPtr.Zero;
    public bool Equal(IntPtr first, IntPtr second) => first != IntPtr.Zero && second != IntPtr.Zero && CFEqual(first, second);
    public void Release(IntPtr element) { if (element != IntPtr.Zero) CFRelease(element); }

    public MacEditorValue Read(IntPtr element)
    {
        var role = String(element, "AXRole");
        var subrole = String(element, "AXSubrole", required: false);
        if (role is not ("AXTextField" or "AXTextArea" or "AXComboBox") || subrole == "AXSecureTextField")
            throw Unsupported();
        var enabled = Copy(element, "AXEnabled");
        try { if (CFGetTypeID(enabled) != CFBooleanGetTypeID() || !CFBooleanGetValue(enabled)) throw Unsupported(); }
        finally { Release(enabled); }
        if (!Settable(element, "AXSelectedText") || !Settable(element, "AXSelectedTextRange")) throw Unsupported();
        // Protected/unsupported fields have already been rejected before value access.
        var text = String(element, "AXValue")!;
        var selection = Copy(element, "AXSelectedTextRange");
        try
        {
            if (CFGetTypeID(selection) != AXValueGetTypeID() || AXValueGetType(selection) != RangeType ||
                !AXValueGetValue(selection, RangeType, out var range) || range.Location < 0 || range.Length < 0 ||
                range.Location > int.MaxValue || range.Length > int.MaxValue) throw Unsupported();
            return new(text, (int)range.Location, (int)range.Length);
        }
        finally { Release(selection); }
    }

    public void ReplaceSelection(IntPtr element, string text)
    {
        var value = CFStringCreateWithCharacters(IntPtr.Zero, Units(text), text.Length);
        try { Set(element, "AXSelectedText", value); }
        finally { Release(value); }
    }

    public void SetSelection(IntPtr element, int start, int length)
    {
        var range = new CFRange { Location = start, Length = length };
        var value = AXValueCreate(RangeType, ref range);
        try { Set(element, "AXSelectedTextRange", value); }
        finally { Release(value); }
    }

    private IntPtr Copy(IntPtr element, string attribute, bool required = true)
    {
        Timeout(element);
        var error = AXUIElementCopyAttributeValue(element, _attributes[attribute], out var value);
        if (error == 0 && value != IntPtr.Zero) return value;
        Release(value);
        if (required) throw Unsupported();
        // Only an absent optional attribute is harmless. A provider timeout or
        // invalid object cannot establish whether a field is secure.
        if (error != -25205 && error != -25212) throw Unsupported();
        return IntPtr.Zero;
    }

    private string? String(IntPtr element, string attribute, bool required = true)
    {
        var value = Copy(element, attribute, required);
        if (value == IntPtr.Zero) return null;
        try
        {
            if (CFGetTypeID(value) != CFStringGetTypeID()) throw Unsupported();
            var count = CFStringGetLength(value);
            if (count < 0 || count > Protocol.MaximumTextUnits) throw Unsupported();
            if (count == 0) return "";
            var units = new ushort[(int)count];
            CFStringGetCharacters(value, new CFRange { Location = 0, Length = count }, units);
            return new string(units.Select(unit => (char)unit).ToArray());
        }
        finally { Release(value); }
    }

    private bool Settable(IntPtr element, string attribute)
    {
        Timeout(element);
        return AXUIElementIsAttributeSettable(element, _attributes[attribute], out var settable) == 0 && settable;
    }

    private void Set(IntPtr element, string attribute, IntPtr value)
    {
        Timeout(element);
        if (value == IntPtr.Zero || AXUIElementSetAttributeValue(element, _attributes[attribute], value) != 0)
            throw MacTextEditor.Error("live_text_uncertain", "The accessibility provider did not confirm the update.");
    }

    private static void Timeout(IntPtr element)
    {
        if (element == IntPtr.Zero || AXUIElementSetMessagingTimeout(element, 0.15f) != 0) throw Unsupported();
    }

    private static InputInjectionException Unsupported() =>
        MacTextEditor.Error("live_text_unsupported", "This Mac field does not provide precise, writable text and selection access.");

    private static ushort[] Units(string text) => text.Select(character => (ushort)character).ToArray();

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        foreach (var value in _attributes.Values) Release(value);
        Release(_system);
    }

    [StructLayout(LayoutKind.Sequential)] private struct CFRange { public nint Location, Length; }
    [DllImport(AX)] [return: MarshalAs(UnmanagedType.I1)] private static extern bool AXIsProcessTrusted();
    [DllImport(AX)] private static extern IntPtr AXUIElementCreateSystemWide();
    [DllImport(AX)] private static extern int AXUIElementSetMessagingTimeout(IntPtr element, float timeout);
    [DllImport(AX)] private static extern int AXUIElementCopyAttributeValue(IntPtr element, IntPtr attribute, out IntPtr value);
    [DllImport(AX)] private static extern int AXUIElementIsAttributeSettable(IntPtr element, IntPtr attribute, [MarshalAs(UnmanagedType.I1)] out bool settable);
    [DllImport(AX)] private static extern int AXUIElementSetAttributeValue(IntPtr element, IntPtr attribute, IntPtr value);
    [DllImport(AX)] private static extern nuint AXValueGetTypeID();
    [DllImport(AX)] private static extern uint AXValueGetType(IntPtr value);
    [DllImport(AX)] [return: MarshalAs(UnmanagedType.I1)] private static extern bool AXValueGetValue(IntPtr value, uint type, out CFRange range);
    [DllImport(AX)] private static extern IntPtr AXValueCreate(uint type, ref CFRange range);
    [DllImport(CF)] private static extern IntPtr CFStringCreateWithCharacters(IntPtr allocator, [In] ushort[] characters, nint count);
    [DllImport(CF)] private static extern nint CFStringGetLength(IntPtr value);
    [DllImport(CF)] private static extern void CFStringGetCharacters(IntPtr value, CFRange range, [Out] ushort[] buffer);
    [DllImport(CF)] private static extern nuint CFGetTypeID(IntPtr value);
    [DllImport(CF)] private static extern nuint CFStringGetTypeID();
    [DllImport(CF)] private static extern nuint CFBooleanGetTypeID();
    [DllImport(CF)] [return: MarshalAs(UnmanagedType.I1)] private static extern bool CFBooleanGetValue(IntPtr value);
    [DllImport(CF)] [return: MarshalAs(UnmanagedType.I1)] private static extern bool CFEqual(IntPtr first, IntPtr second);
    [DllImport(CF)] private static extern void CFRelease(IntPtr value);
}
