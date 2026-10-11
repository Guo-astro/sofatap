using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace SofaTap;

// UI Automation metadata supports native and browser controls without relying on an HWND
// class name. These declarations are interface prefixes from Microsoft's UIAutomationClient.h.
[SupportedOSPlatform("windows")]
internal sealed class WindowsTextFocusProbe : ITextFocusProbe
{
    private IAutomation? _automation;
    private IElement? _previous;
    private string? _identity;
    private bool _initialized;

    internal WindowsTextFocusProbe()
    {
        Marshal.ThrowExceptionForHR(CoInitializeEx(IntPtr.Zero, 0)); // Dedicated MTA thread.
        _initialized = true;
        try
        {
            var clsid = new Guid("ff48dba4-60ef-4201-aa87-54103eef594e");
            var iid = typeof(IAutomation).GUID;
            Marshal.ThrowExceptionForHR(CoCreateInstance(ref clsid, IntPtr.Zero, 1, ref iid, out _automation));
        }
        catch { Dispose(); throw; }
    }

    public TextFocusSnapshot Read()
    {
        if (_automation is null) return new(TextFocusKind.Unknown);
        IElement? element = null;
        IElement? current = null;
        try
        {
            _automation.GetFocusedElement(out element);
            if (element is null) return Unknown();
            var focused = BooleanProperty(element, 30008);
            var enabled = BooleanProperty(element, 30010);
            var password = BooleanProperty(element, 30019);
            bool? valueAvailable = null, valueReadOnly = null, textReadOnly = null;
            if (focused == true && enabled == true && password == false)
            {
                valueAvailable = BooleanProperty(element, 30043);
                if (valueAvailable == true) valueReadOnly = BooleanProperty(element, 30046);
                if (valueReadOnly is null && BooleanProperty(element, 30040) == true)
                    textReadOnly = ReadTextIsReadOnly(element);
            }
            var kind = TextFocusRules.Windows(focused, enabled, password, valueAvailable, valueReadOnly, textReadOnly);
            _automation.GetFocusedElement(out current);
            if (current is null) return Unknown();
            _automation.CompareElements(element, current, out var stillFocused);
            if (!stillFocused) return Unknown();
            var same = false;
            if (_previous is not null) _automation.CompareElements(element, _previous, out same);
            if (!same)
            {
                Release(_previous);
                _previous = element; element = null;
                _identity = Guid.NewGuid().ToString("N");
            }
            return new(kind, _identity);
        }
        catch (Exception error) when (error is COMException or InvalidCastException or InvalidComObjectException)
        { return Unknown(); }
        finally { Release(current); Release(element); }
    }

    private TextFocusSnapshot Unknown()
    {
        Release(_previous); _previous = null; _identity = null;
        return new(TextFocusKind.Unknown);
    }
    private static bool? BooleanProperty(IElement element, int id)
    {
        object? value = null;
        try
        {
            // Ignoring defaults distinguishes false from an unsupported property.
            element.GetCurrentPropertyValueEx(id, true, out value);
            return value is bool result ? result : null;
        }
        finally { Release(value); }
    }
    private static bool? ReadTextIsReadOnly(IElement element)
    {
        object? pattern = null, value = null;
        ITextRange? range = null;
        try
        {
            element.GetCurrentPattern(10014, out pattern);
            if (pattern is not ITextPattern text) return null;
            text.GetDocumentRange(out range);
            if (range is null) return null;
            // Reads the IsReadOnly boolean only. No GetText, selected text or document values.
            range.GetAttributeValue(40015, out value);
            return value is bool readOnly ? readOnly : null;
        }
        catch (COMException) { return null; }
        finally { Release(value); Release(range); Release(pattern); }
    }
    private static void Release(object? value)
    {
        // One release per returned COM reference, rather than invalidating shared RCWs.
        if (value is not null && Marshal.IsComObject(value)) Marshal.ReleaseComObject(value);
    }
    public void Dispose()
    {
        Unknown(); Release(_automation); _automation = null;
        if (_initialized) { CoUninitialize(); _initialized = false; }
    }

    [DllImport("ole32.dll")] private static extern int CoInitializeEx(IntPtr reserved, uint flags);
    [DllImport("ole32.dll")] private static extern void CoUninitialize();
    [DllImport("ole32.dll")] private static extern int CoCreateInstance(ref Guid clsid, IntPtr outer, uint context, ref Guid iid,
        [MarshalAs(UnmanagedType.Interface)] out IAutomation automation);

    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X; public int Y; }
    [ComImport, Guid("30cbe57d-d9d0-452a-ab13-7ac5ac4825ee"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAutomation
    {
        void CompareElements(IElement first, IElement second, [MarshalAs(UnmanagedType.Bool)] out bool same);
        void CompareRuntimeIds(IntPtr first, IntPtr second, out int same);
        void GetRootElement(out IElement element);
        void ElementFromHandle(IntPtr window, out IElement element);
        void ElementFromPoint(Point point, out IElement element);
        void GetFocusedElement(out IElement element);
    }
    [ComImport, Guid("d22108aa-8ac5-49a5-837b-37bbb3d7591e"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IElement
    {
        void SetFocus();
        void GetRuntimeId(out IntPtr id);
        void FindFirst(int scope, IntPtr condition, out IntPtr found);
        void FindAll(int scope, IntPtr condition, out IntPtr found);
        void FindFirstBuildCache(int scope, IntPtr condition, IntPtr cache, out IntPtr found);
        void FindAllBuildCache(int scope, IntPtr condition, IntPtr cache, out IntPtr found);
        void BuildUpdatedCache(IntPtr cache, out IntPtr updated);
        void GetCurrentPropertyValue(int id, [MarshalAs(UnmanagedType.Struct)] out object value);
        void GetCurrentPropertyValueEx(int id, [MarshalAs(UnmanagedType.Bool)] bool ignoreDefault, [MarshalAs(UnmanagedType.Struct)] out object value);
        void GetCachedPropertyValue(int id, [MarshalAs(UnmanagedType.Struct)] out object value);
        void GetCachedPropertyValueEx(int id, [MarshalAs(UnmanagedType.Bool)] bool ignoreDefault, [MarshalAs(UnmanagedType.Struct)] out object value);
        void GetCurrentPatternAs(int id, ref Guid iid, out IntPtr pattern);
        void GetCachedPatternAs(int id, ref Guid iid, out IntPtr pattern);
        void GetCurrentPattern(int id, [MarshalAs(UnmanagedType.IUnknown)] out object pattern);
    }
    [ComImport, Guid("32eba289-3583-42c9-9c59-3b6d9a1e9b6a"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ITextPattern
    {
        void RangeFromPoint(Point point, out IntPtr range);
        void RangeFromChild(IElement child, out IntPtr range);
        void GetSelection(out IntPtr ranges);
        void GetVisibleRanges(out IntPtr ranges);
        void GetDocumentRange(out ITextRange range);
    }
    [ComImport, Guid("a543cc6a-f4ae-494b-8239-c814481187a8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ITextRange
    {
        void Clone(out IntPtr range);
        void Compare(IntPtr range, out int same);
        void CompareEndpoints(int source, IntPtr range, int target, out int result);
        void ExpandToEnclosingUnit(int unit);
        void FindAttribute(int attribute, [MarshalAs(UnmanagedType.Struct)] object value, int backward, out IntPtr found);
        void FindText(IntPtr text, int backward, int ignoreCase, out IntPtr found);
        void GetAttributeValue(int attribute, [MarshalAs(UnmanagedType.Struct)] out object value);
    }
}
