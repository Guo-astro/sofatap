using System.Text;
using System.Text.Json;
using SofaTap;

var passed = 0;
void Check(bool value, string name) { if (!value) throw new Exception("FAIL: " + name); passed++; }
ActionMessage Parse(string body) => Protocol.Parse(Encoding.UTF8.GetBytes(body));
string Message(string fields, string? id = null) => "{\"id\":\"" + (id ?? Guid.NewGuid().ToString("D")) + "\"," + fields + "}";
void Reject(string body, string name)
{
    try { Parse(body); throw new Exception("FAIL: accepted " + name); }
    catch (Exception error) when (error is ProtocolException or JsonException or InvalidOperationException) { passed++; }
}

Check(WindowsInput.NativeInputSize == (IntPtr.Size == 8 ? 40 : 28), "native INPUT architecture layout");
Check(WindowsInput.NormalizeWindowsNewlines("a\nb\r\nc\rd") == "a\rb\rc\rd", "Windows newline normalization preserves one paragraph break");
Check(WindowsInput.NormalizeWindowsNewlines("hello👋") == "hello👋", "no appended Enter or changed surrogate pairs");
Check(WindowsInput.ShortcutFailureReleaseCount(0) == 0, "failed zero-input shortcut releases no unowned key");
Check(WindowsInput.ShortcutFailureReleaseCount(1) == 1 && WindowsInput.ShortcutFailureReleaseCount(2) == 2, "partial shortcut releases only accepted outstanding downs");
Check(WindowsInput.ShortcutFailureReleaseCount(3) == 1 && WindowsInput.ShortcutFailureReleaseCount(4) == 0, "completed keyups excluded from failure cleanup");
Check(!new DryRunInput().Available, "dry-run availability is false");
var moved = Parse(Message("\"type\":\"move\",\"dx\":0.25,\"dy\":-500"));
Check(moved.Dx == 0.25 && moved.Dy == -500, "fractional move range");
Check(Parse(Message("\"type\":\"scroll\",\"dx\":1200,\"dy\":-1200")).Dy == -1200, "scroll limits");
var text = "你好 Windows 👋\n第二行";
var committed = Parse(Message("\"type\":\"text\",\"text\":" + JsonSerializer.Serialize(text)));
Check(committed.Text == text && committed.Text.Length == text.Length, "Chinese emoji UTF-16 preserved");
Check(Parse(Message("\"type\":\"text\",\"text\":" + JsonSerializer.Serialize(new string('x', 16000)))).Text!.Length == 16000, "maximum text units");
Check(Parse(Message("\"type\":\"key\",\"key\":\"a\",\"modifiers\":[\"ctrl\"]")).Modifiers!.SequenceEqual(["ctrl"]), "allowed shortcut");
Reject(Message("\"type\":\"move\",\"dx\":500.1,\"dy\":0"), "move overflow");
Reject(Message("\"type\":\"move\",\"dx\":1e999,\"dy\":0"), "infinite numeric overflow");
Reject(Message("\"type\":\"scroll\",\"dx\":0,\"dy\":1201"), "scroll overflow");
Reject(Message("\"type\":\"click\",\"button\":\"middle\""), "unsupported button");
Reject(Message("\"type\":\"button\",\"button\":\"left\",\"down\":1"), "nonboolean down");
Reject(Message("\"type\":\"text\",\"text\":\"x\",\"extra\":1"), "unknown field");
Reject(Message("\"type\":\"text\",\"type\":\"ping\",\"text\":\"x\""), "duplicate field");
Reject(Message("\"type\":\"key\",\"key\":\"f12\",\"modifiers\":[]"), "unsupported key");
Reject(Message("\"type\":\"key\",\"key\":\"a\",\"modifiers\":[\"ctrl\",\"ctrl\"]"), "duplicate modifier");
Reject(Message("\"type\":\"key\",\"key\":\"a\",\"modifiers\":[\"meta\"]"), "unsupported modifier");
Reject(Message("\"type\":\"ping\"", "invalid"), "malformed UUID");
Reject(Message("\"type\":\"exec\",\"command\":\"calc\""), "executable command");
Reject(Message("\"type\":\"text\",\"text\":" + JsonSerializer.Serialize(new string('x', 16001))), "text overflow");
Reject(Message("\"type\":\"text\",\"text\":\"\\uD800\""), "unpaired surrogate");
Reject(Message("\"type\":\"text\",\"text\":\"\\u0000\""), "NUL text");
Reject(new string(' ', Protocol.MaximumFrameBytes + 1), "frame cap");
Reject("[]", "nonobject JSON");

var fake = new FakeInput(); var session = new ActionSession(fake);
Check(session.Execute(committed).Ok && fake.Count == 1, "successful injection acknowledged");
Check(session.Execute(committed).Ok && fake.Count == 1, "same action deduplicated");
Check(session.Execute(committed with { Id = committed.Id.ToUpperInvariant() }).Ok && fake.Count == 1, "UUID case deduplication");
Check(!session.Execute(committed with { Text = "different" }).Ok && fake.Count == 1, "conflicting ID rejected without injection");
Check(session.Execute(new(Guid.NewGuid().ToString("D"), "ping")).Ok && fake.Count == 1, "ping never injects");
fake.Fail = true;
var failed = committed with { Id = Guid.NewGuid().ToString("D") };
var rejected = session.Execute(failed);
Check(!rejected.Ok && rejected.Error!.StartsWith("input_partial:") && fake.Count == 2, "partial injection status propagated");
Check(!session.Execute(failed).Ok && fake.Count == 2, "failed partial action never retried");
var bounded = new ActionSession(new FakeInput(), 1);
Check(bounded.Execute(committed).Ok, "dedup bounded session first action");
try { bounded.Execute(committed with { Id = Guid.NewGuid().ToString("D") }); throw new Exception("FAIL: action cap accepted"); }
catch (ProtocolException) { passed++; }

var directory = Path.Combine(Path.GetTempPath(), "sofatap-host-tests-" + Guid.NewGuid().ToString("N"));
try
{
    string token; string fingerprint;
    using (var credentials = Credentials.LoadOrCreate(directory))
    {
        token = credentials.Token; fingerprint = credentials.Fingerprint;
        Check(token.Length == 43 && fingerprint.Length == 64, "random token and pin shape");
        Check(credentials.Certificate.HasPrivateKey, "TLS private key present");
        Check(credentials.Certificate.NotAfter.ToUniversalTime() - credentials.Certificate.NotBefore.ToUniversalTime() <= TimeSpan.FromDays(366), "certificate duration meets Apple SSL maximum validity constraint");
        Check(NetworkAddresses.LocalIPv4().All(address => credentials.CertificateIPv4.Contains(address)), "every advertised LAN address has certificate SAN");
        try { using var duplicate = Credentials.LoadOrCreate(directory); throw new Exception("FAIL: concurrent profile lock"); }
        catch (InvalidOperationException) { passed++; }
    }
    using (var credentials = Credentials.LoadOrCreate(directory))
        Check(credentials.Token == token && credentials.Fingerprint == fingerprint, "pairing persists across receiver restart");
    if (!OperatingSystem.IsWindows())
        Check(File.GetUnixFileMode(Path.Combine(directory, "pairing.dat")) == (UnixFileMode.UserRead | UnixFileMode.UserWrite), "pairing file user-only permissions");
}
finally { Directory.Delete(directory, true); }
Console.WriteLine($"PASS: {passed} host checks. Windows physical input is not exercised by this runner.");

sealed class FakeInput : IInputInjector
{
    public int Count { get; private set; }
    public bool Fail { get; set; }
    public bool Available => true;
    public void Apply(ActionMessage action) { Count++; if (Fail) throw new InputInjectionException("input_partial: injected prefix; delivery uncertain"); }
    public void ReleaseAll() { }
}
