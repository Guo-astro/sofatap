using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using SofaTap;

internal static class ReceiverDistributionChecks
{
    internal static void Run(Action<bool, string> check)
    {
        var store = ReceiverDistribution.IsMacAppStore;
        var assembly = typeof(MacInput).Assembly;
        var names = new[] { "SofaTap.MacTextFocusProbe", "SofaTap.MacTextEditor", "SofaTap.MacTextEditorAccess" };
        check(names.All(name => (assembly.GetType(name) is null) == store),
            "store assembly excludes AX focus and live editor types; direct download retains them");
        var nativeMethods = assembly.GetTypes().SelectMany(type => type.GetMethods(
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance));
        var imports = nativeMethods.Select(method => (method.Name, Import: method.GetCustomAttribute<DllImportAttribute>()))
            .Where(item => item.Import is not null).ToArray();
        check(imports.Any(item => item.Name.StartsWith("AX", StringComparison.Ordinal)) == !store,
            "store assembly has no AX native imports; direct-download AX imports remain");
        check(imports.Any(item => item.Name == "CGPreflightPostEventAccess") &&
            imports.Any(item => item.Name == "CGEventPost"),
            "basic receiver retains public Core Graphics posting and permission APIs");

        var hello = JsonSerializer.SerializeToElement(ReceiverServer.CreateHello("Fixture", "macos", false,
            "ready", new("editable", 7), liveTextSupported: true), new JsonSerializerOptions(JsonSerializerDefaults.Web));
        check(hello.GetProperty("inputAvailable").GetBoolean(), "store basic input readiness is retained");
        check(hello.GetProperty("liveText").ValueKind == (store ? JsonValueKind.Null : JsonValueKind.Object),
            "store handshake cannot advertise live text even when a caller asks for it");
        check(hello.GetProperty("textFocus").GetProperty("state").GetString() == (store ? "unknown" : "editable"),
            "store handshake cannot advertise focused input detection");
        check(ReceiverDistribution.CreateTextFocus(true) is null && ReceiverDistribution.CreateTextEditorFactory(true) is null,
            "dry-run startup never creates native focus or editor providers");
        if (store)
        {
            check(ReceiverDistribution.CreateTextFocus(false) is null && ReceiverDistribution.CreateTextEditorFactory(false) is null,
                "store normal startup does not create native focus or editing providers");
            using var focus = TextFocusProbe.Create();
            check(focus.Read().Kind == TextFocusKind.Unknown, "store fallback focus probe remains unknown without native inspection");
            foreach (var directory in new string?[] { null, "", " ", "relative/path" })
            {
                var refused = false;
                try { ReceiverDistribution.DataDirectory(directory); }
                catch (ArgumentException) { refused = true; }
                check(refused, "store requires explicit absolute data directory, never direct-download fallback");
            }
        }
        else
        {
            check(ReceiverDistribution.DataDirectory(null) == Credentials.DefaultDirectory,
                "direct-download profile location stays unchanged");
        }
        var absolute = Path.Combine(Path.GetTempPath(), "sofatap-container-policy-fixture");
        check(ReceiverDistribution.DataDirectory(absolute) == Path.GetFullPath(absolute),
            "absolute app-container directory is passed through without filesystem access");

        var sink = new RecordingMacSink();
        var input = new MacInput(sink);
        input.Apply(new("", "text", Text: "中文 👋"));
        check(string.Concat(sink.Events.Where(item => item.Down).Select(item => item.Unicode)) == "中文 👋",
            "basic Mac Unicode text stays intact using only recording events");
        sink.Events.Clear();
        input.Apply(new("", "key", Key: "backspace", Modifiers: []));
        check(sink.Events.Count == 2 && sink.Events[0].KeyCode == 0x33 && sink.Events[0].Down &&
            !sink.Events[1].Down && sink.HeldKeys.Count == 0,
            "basic Mac backspace emits one key pair and releases the key");
        var session = new ActionSession(input);
        var rejected = session.Execute(new(Guid.NewGuid().ToString("D"), "textBegin"));
        check(!rejected.Ok && rejected.Error!.StartsWith("live_text_unsupported:", StringComparison.Ordinal),
            "basic session rejects live editing instead of pretending it synchronized");
    }
}
