using System.Runtime.InteropServices;
using System.Text;

namespace SofaTap;

internal sealed class MacTextFocusProbe : ITextFocusProbe
{
    private const string AX = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices";
    private const string CF = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    private readonly IntPtr _system;
    private readonly Dictionary<string, IntPtr> _attributes = new();
    private IntPtr _previous;
    private string? _identity;

    internal MacTextFocusProbe()
    {
        _system = AXUIElementCreateSystemWide();
        if (_system != IntPtr.Zero) AXUIElementSetMessagingTimeout(_system, 0.15f);
        foreach (var name in new[] { "AXFocusedUIElement", "AXRole", "AXSubrole", "AXEnabled", "AXValue" })
            _attributes[name] = CFStringCreateWithCString(IntPtr.Zero, name, 0x08000100);
    }

    public TextFocusSnapshot Read()
    {
        // A plain trust query does not prompt or open System Settings.
        if (_system == IntPtr.Zero || !AXIsProcessTrusted()) return Unknown();
        var element = Copy(_system, "AXFocusedUIElement");
        if (element == IntPtr.Zero) return Unknown();
        try
        {
            var role = ReadString(element, "AXRole");
            var subrole = ReadString(element, "AXSubrole");
            var enabled = ReadBoolean(element, "AXEnabled");
            bool? writable = AXUIElementIsAttributeSettable(element, _attributes["AXValue"], out var settable) == 0 ? settable : null;
            var kind = TextFocusRules.Mac(role, subrole, enabled, writable);
            // Reject a torn sample if focus changed while the target app answered metadata queries.
            var current = Copy(_system, "AXFocusedUIElement");
            try { if (current == IntPtr.Zero || !CFEqual(element, current)) return Unknown(); }
            finally { if (current != IntPtr.Zero) CFRelease(current); }
            if (_previous == IntPtr.Zero || !CFEqual(_previous, element))
            {
                if (_previous != IntPtr.Zero) CFRelease(_previous);
                _previous = CFRetain(element);
                _identity = Guid.NewGuid().ToString("N");
            }
            return new(kind, _identity);
        }
        finally { CFRelease(element); }
    }

    private TextFocusSnapshot Unknown()
    {
        if (_previous != IntPtr.Zero) { CFRelease(_previous); _previous = IntPtr.Zero; }
        _identity = null;
        return new(TextFocusKind.Unknown);
    }
    private IntPtr Copy(IntPtr element, string attribute) =>
        AXUIElementCopyAttributeValue(element, _attributes[attribute], out var value) == 0 ? value : IntPtr.Zero;
    private string? ReadString(IntPtr element, string attribute)
    {
        var value = Copy(element, attribute);
        if (value == IntPtr.Zero) return null;
        try
        {
            if (CFGetTypeID(value) != CFStringGetTypeID()) return null;
            var buffer = new StringBuilder(128);
            return CFStringGetCString(value, buffer, 128, 0x08000100) ? buffer.ToString() : null;
        }
        finally { CFRelease(value); }
    }
    private bool? ReadBoolean(IntPtr element, string attribute)
    {
        var value = Copy(element, attribute);
        if (value == IntPtr.Zero) return null;
        try { return CFGetTypeID(value) == CFBooleanGetTypeID() ? CFBooleanGetValue(value) : null; }
        finally { CFRelease(value); }
    }
    public void Dispose()
    {
        Unknown();
        foreach (var value in _attributes.Values) if (value != IntPtr.Zero) CFRelease(value);
        if (_system != IntPtr.Zero) CFRelease(_system);
    }

    [DllImport(AX)] [return: MarshalAs(UnmanagedType.I1)] private static extern bool AXIsProcessTrusted();
    [DllImport(AX)] private static extern IntPtr AXUIElementCreateSystemWide();
    [DllImport(AX)] private static extern int AXUIElementSetMessagingTimeout(IntPtr element, float timeout);
    [DllImport(AX)] private static extern int AXUIElementCopyAttributeValue(IntPtr element, IntPtr attribute, out IntPtr value);
    [DllImport(AX)] private static extern int AXUIElementIsAttributeSettable(IntPtr element, IntPtr attribute, [MarshalAs(UnmanagedType.I1)] out bool settable);
    [DllImport(CF)] private static extern IntPtr CFStringCreateWithCString(IntPtr allocator, [MarshalAs(UnmanagedType.LPUTF8Str)] string value, uint encoding);
    [DllImport(CF)] [return: MarshalAs(UnmanagedType.I1)] private static extern bool CFStringGetCString(IntPtr value, StringBuilder buffer, nint size, uint encoding);
    [DllImport(CF)] private static extern nuint CFGetTypeID(IntPtr value);
    [DllImport(CF)] private static extern nuint CFStringGetTypeID();
    [DllImport(CF)] private static extern nuint CFBooleanGetTypeID();
    [DllImport(CF)] [return: MarshalAs(UnmanagedType.I1)] private static extern bool CFBooleanGetValue(IntPtr value);
    [DllImport(CF)] [return: MarshalAs(UnmanagedType.I1)] private static extern bool CFEqual(IntPtr first, IntPtr second);
    [DllImport(CF)] private static extern IntPtr CFRetain(IntPtr value);
    [DllImport(CF)] private static extern void CFRelease(IntPtr value);
}
