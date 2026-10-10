using System.Runtime.InteropServices;

namespace SofaTap;

public interface IInputInjector
{
    bool Available { get; }
    void Apply(ActionMessage action);
    void ReleaseAll();
}
public sealed class InputInjectionException(string message) : Exception(message);
public sealed class DryRunInput : IInputInjector
{
    public bool Available => false;
    public void Apply(ActionMessage action) { }
    public void ReleaseAll() { }
}

public sealed class WindowsInput : IInputInjector
{
    private const uint Mouse = 0, Keyboard = 1;
    private const uint Move = 0x0001, LeftDown = 0x0002, LeftUp = 0x0004, RightDown = 0x0008, RightUp = 0x0010;
    private const uint Wheel = 0x0800, HorizontalWheel = 0x1000, KeyUp = 0x0002, Unicode = 0x0004, Extended = 0x0001;
    private readonly HashSet<string> _held = [];
    private double _fractionX, _fractionY, _scrollX, _scrollY;
    private readonly object _gate = new();
    private static readonly Dictionary<string, ushort> VirtualKeys = new()
    {
        ["enter"] = 0x0D, ["tab"] = 0x09, ["escape"] = 0x1B, ["backspace"] = 0x08, ["delete"] = 0x2E,
        ["up"] = 0x26, ["down"] = 0x28, ["left"] = 0x25, ["right"] = 0x27, ["home"] = 0x24,
        ["end"] = 0x23, ["pageup"] = 0x21, ["pagedown"] = 0x22, ["space"] = 0x20,
        ["a"] = 0x41, ["c"] = 0x43, ["v"] = 0x56, ["x"] = 0x58, ["z"] = 0x5A,
        ["ctrl"] = 0x11, ["alt"] = 0x12, ["shift"] = 0x10, ["win"] = 0x5B
    };
    private static readonly HashSet<string> ExtendedKeys = ["delete", "up", "down", "left", "right", "home", "end", "pageup", "pagedown", "win"];

    public bool Available
    {
        get
        {
            if (!OperatingSystem.IsWindows() || !Environment.UserInteractive) return false;
            var desktop = Native.OpenInputDesktop(0, false, 0x0001);
            if (desktop == IntPtr.Zero) return false;
            Native.CloseDesktop(desktop);
            return true;
        }
    }
    public void Apply(ActionMessage action)
    {
        lock (_gate)
        {
            if (!Available) throw new InputInjectionException("input_unavailable: No interactive Windows desktop is available. Sign in and unlock the PC.");
            switch (action.Type)
            {
                case "move":
                    _fractionX += action.Dx; _fractionY += action.Dy;
                    var x = (int)_fractionX; var y = (int)_fractionY;
                    if (x != 0 || y != 0) Submit([MouseEvent(Move, x, y)]);
                    _fractionX -= x; _fractionY -= y;
                    break;
                case "scroll":
                    _scrollX += action.Dx; _scrollY += action.Dy;
                    var sx = (int)_scrollX; var sy = (int)_scrollY;
                    var scrollEvents = new List<Native.Input>();
                    if (sx != 0) scrollEvents.Add(MouseEvent(HorizontalWheel, data: sx));
                    if (sy != 0) scrollEvents.Add(MouseEvent(Wheel, data: sy));
                    Submit(scrollEvents.ToArray());
                    _scrollX -= sx; _scrollY -= sy;
                    break;
                case "click":
                    Submit([MouseEvent(ButtonFlag(action.Button!, true)), MouseEvent(ButtonFlag(action.Button!, false))]);
                    _held.Remove(action.Button!);
                    break;
                case "button":
                    if (action.Down == _held.Contains(action.Button!)) break;
                    Submit([MouseEvent(ButtonFlag(action.Button!, action.Down))]);
                    if (action.Down) _held.Add(action.Button!); else _held.Remove(action.Button!);
                    break;
                case "key":
                    if (action.Modifiers!.Append(action.Key!).Any(key => (Native.GetAsyncKeyState(VirtualKeys[key]) & 0x8000) != 0))
                        throw new InputInjectionException("input_busy: Release the physical keyboard keys used by this shortcut, then try again.");
                    var keyEvents = new List<Native.Input>();
                    foreach (var modifier in action.Modifiers!) keyEvents.Add(KeyEvent(modifier, false));
                    keyEvents.Add(KeyEvent(action.Key!, false)); keyEvents.Add(KeyEvent(action.Key!, true));
                    foreach (var modifier in action.Modifiers.Reverse()) keyEvents.Add(KeyEvent(modifier, true));
                    Submit(keyEvents.ToArray());
                    break;
                case "text":
                    // SendInput consumes UTF-16 code units; do not enumerate runes or split surrogate pairs.
                    var textUnits = NormalizeWindowsNewlines(action.Text!);
                    var textEvents = new Native.Input[textUnits.Length * 2];
                    for (var index = 0; index < textUnits.Length; index++)
                    {
                        textEvents[index * 2] = UnicodeEvent(textUnits[index], false);
                        textEvents[index * 2 + 1] = UnicodeEvent(textUnits[index], true);
                    }
                    Submit(textEvents);
                    break;
            }
        }
    }
    public void ReleaseAll()
    {
        lock (_gate)
        {
            if (OperatingSystem.IsWindows())
            {
                var events = _held.Select(button => MouseEvent(ButtonFlag(button, false))).ToArray();
                if (events.Length > 0) Native.SendInput((uint)events.Length, events, Marshal.SizeOf<Native.Input>());
            }
            _held.Clear(); _fractionX = 0; _fractionY = 0; _scrollX = 0; _scrollY = 0;
        }
    }
    private void Submit(Native.Input[] events)
    {
        if (events.Length == 0) return;
        var accepted = Native.SendInput((uint)events.Length, events, Marshal.SizeOf<Native.Input>());
        if (accepted == events.Length) return;
        var error = Marshal.GetLastPInvokeError();
        // A short write can leave injected keys or a button down. Always attempt release.
        var releases = BuildFailureReleases(events, checked((int)accepted), _held);
        if (releases.Length > 0) Native.SendInput((uint)releases.Length, releases, Marshal.SizeOf<Native.Input>());
        _held.Clear();
        throw new InputInjectionException($"{(accepted > 0 ? "input_partial" : "input_failed")}: Windows accepted {accepted} of {events.Length} input events (error {error}). {(accepted > 0 ? "Delivery is partial." : "No input events were accepted.")} Focus a normal desktop app; administrator apps and secure desktop may reject input (UIPI). Do not resend text automatically.");
    }
    private static Native.Input[] BuildFailureReleases(Native.Input[] attempted, int accepted, IEnumerable<string> held)
    {
        var keys = new Dictionary<(ushort Key, ushort Scan, uint Flags), Native.Input>();
        var buttons = held.ToHashSet(StringComparer.Ordinal);
        foreach (var item in attempted.Take(accepted))
        {
            if (item.Type == Keyboard)
            {
                var keyboard = item.Union.Keyboard;
                var identity = (keyboard.VirtualKey, keyboard.Scan, keyboard.Flags & ~KeyUp);
                if ((keyboard.Flags & KeyUp) != 0) keys.Remove(identity);
                else { var release = item; release.Union.Keyboard.Flags |= KeyUp; keys[identity] = release; }
            }
            else if (item.Type == Mouse)
            {
                var flags = item.Union.Mouse.Flags;
                if ((flags & LeftDown) != 0) buttons.Add("left");
                if ((flags & LeftUp) != 0) buttons.Remove("left");
                if ((flags & RightDown) != 0) buttons.Add("right");
                if ((flags & RightUp) != 0) buttons.Remove("right");
            }
        }
        return keys.Values.Concat(buttons.Select(button => MouseEvent(ButtonFlag(button, false)))).ToArray();
    }
    // Pure diagnostic used by tests; no Windows API calls or real input are made.
    internal static int ShortcutFailureReleaseCount(int accepted)
    {
        Native.Input[] shortcut = [KeyEvent("ctrl", false), KeyEvent("a", false), KeyEvent("a", true), KeyEvent("ctrl", true)];
        return BuildFailureReleases(shortcut, accepted, []).Length;
    }
    private static uint ButtonFlag(string button, bool down) => (button, down) switch
    { ("left", true) => LeftDown, ("left", false) => LeftUp, ("right", true) => RightDown, _ => RightUp };
    private static Native.Input MouseEvent(uint flags, int x = 0, int y = 0, int data = 0) => new()
    { Type = Mouse, Union = new Native.InputUnion { Mouse = new() { Dx = x, Dy = y, MouseData = unchecked((uint)data), Flags = flags } } };
    private static Native.Input KeyEvent(string key, bool up) => new()
    { Type = Keyboard, Union = new Native.InputUnion { Keyboard = new() { VirtualKey = VirtualKeys[key], Flags = (up ? KeyUp : 0) | (ExtendedKeys.Contains(key) ? Extended : 0) } } };
    private static Native.Input UnicodeEvent(char unit, bool up) => new()
    { Type = Keyboard, Union = new Native.InputUnion { Keyboard = new() { Scan = unit, Flags = Unicode | (up ? KeyUp : 0) } } };

    public static string NormalizeWindowsNewlines(string text) => text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\n', '\r');

    public static int NativeInputSize => Marshal.SizeOf<Native.Input>();
    private static class Native
    {
        [StructLayout(LayoutKind.Sequential)] public struct Input { public uint Type; public InputUnion Union; }
        [StructLayout(LayoutKind.Explicit)] public struct InputUnion
        {
            [FieldOffset(0)] public MouseInput Mouse;
            [FieldOffset(0)] public KeyboardInput Keyboard;
            [FieldOffset(0)] public HardwareInput Hardware;
        }
        [StructLayout(LayoutKind.Sequential)] public struct MouseInput { public int Dx, Dy; public uint MouseData, Flags, Time; public IntPtr ExtraInfo; }
        [StructLayout(LayoutKind.Sequential)] public struct KeyboardInput { public ushort VirtualKey, Scan; public uint Flags, Time; public IntPtr ExtraInfo; }
        [StructLayout(LayoutKind.Sequential)] public struct HardwareInput { public uint Message; public ushort ParamL, ParamH; }
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int virtualKey);
        [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint count, [In] Input[] inputs, int size);
        [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr OpenInputDesktop(uint flags, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint access);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool CloseDesktop(IntPtr desktop);
    }
}
