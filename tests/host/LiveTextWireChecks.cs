using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;
using SofaTap;

internal static class LiveTextWireChecks
{
    // Exercise the production TLS, authentication, WebSocket framing and JSON serializers.
    // The only injected backends are these in-memory fakes: this test cannot send desktop
    // input, query accessibility, access a user's pairing profile or open a desktop window.
    internal static async Task Run(Action<bool, string> check)
    {
        var directory = Path.Combine(Path.GetTempPath(), "sofatap-live-wire-" + Guid.NewGuid().ToString("N"));
        try
        {
            using var credentials = Credentials.LoadOrCreate(directory);
            var input = new WireInput();
            var editor = new WireEditor();
            var editorCreations = 0;
            var server = new ReceiverServer(new(false, directory, 0), credentials, input,
                textEditorFactory: () => { editorCreations++; return editor; });
            await using var app = server.Build();
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            try
            {
                await app.StartAsync(deadline.Token);
                var address = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!
                    .Addresses.Single();
                var uri = new UriBuilder("wss", "127.0.0.1", new Uri(address).Port, "/control").Uri;
                using var socket = new ClientWebSocket();
                socket.Options.Proxy = null;
                var expectedCertificate = SHA256.HashData(credentials.Certificate.RawData);
                var matchedPin = false;
                socket.Options.RemoteCertificateValidationCallback = (_, certificate, _, _) =>
                {
                    matchedPin = certificate is not null && CryptographicOperations.FixedTimeEquals(
                        SHA256.HashData(certificate.GetRawCertData()), expectedCertificate);
                    return matchedPin;
                };
                socket.Options.SetRequestHeader("Authorization", "Bearer " + credentials.Token);
                await socket.ConnectAsync(uri, deadline.Token);
                var hello = await Receive(socket, deadline.Token);
                if (ReceiverDistribution.IsMacAppStore)
                {
                    check(matchedPin && hello.Json.GetProperty("inputAvailable").GetBoolean() &&
                        !hello.Json.TryGetProperty("liveText", out _) &&
                        hello.Json.GetProperty("textFocus").GetProperty("state").GetString() == "unknown" &&
                        editorCreations == 0,
                        "store wire hello never advertises inspection or creates an injected live editor");
                    await Send(socket, new { id = Guid.NewGuid().ToString("D"), type = "textBegin" }, deadline.Token);
                    var refused = await Receive(socket, deadline.Token);
                    check(!refused.Json.GetProperty("ok").GetBoolean() && editorCreations == 0 && input.Applied == 0,
                        "store wire rejects live editing without creating a provider or injecting input");
                    await Send(socket, new { id = Guid.NewGuid().ToString("D"), type = "text", text = "中文 👋" }, deadline.Token);
                    var textAck = await Receive(socket, deadline.Token);
                    await Send(socket, new { id = Guid.NewGuid().ToString("D"), type = "key", key = "backspace", modifiers = Array.Empty<string>() }, deadline.Token);
                    var keyAck = await Receive(socket, deadline.Token);
                    check(textAck.Json.GetProperty("ok").GetBoolean() && keyAck.Json.GetProperty("ok").GetBoolean() &&
                        input.Applied == 2 && editorCreations == 0,
                        "store wire still delivers ordinary text and backspace to the fake input backend");
                    await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Fixture complete.", deadline.Token);
                    return;
                }
                check(matchedPin && hello.Json.GetProperty("type").GetString() == "hello" &&
                    hello.Json.GetProperty("inputAvailable").GetBoolean() &&
                    !hello.Json.GetProperty("dryRun").GetBoolean() &&
                    hello.Json.GetProperty("liveText").GetProperty("version").GetInt32() == 1,
                    "real pinned TLS receiver hello advertises live text with ready fake input");

                var beginId = Guid.NewGuid().ToString("D");
                await Send(socket, new { id = beginId, type = "textBegin" }, deadline.Token);
                var begun = await Receive(socket, deadline.Token);
                var snapshot = begun.Json.GetProperty("liveText");
                var session = snapshot.GetProperty("session").GetString()!;
                check(begun.Json.GetProperty("type").GetString() == "ack" &&
                    begun.Json.GetProperty("id").GetString() == beginId && begun.Json.GetProperty("ok").GetBoolean() &&
                    Guid.TryParseExact(session, "D", out _) && snapshot.GetProperty("revision").GetInt32() == 0 &&
                    snapshot.GetProperty("text").GetString() == WireEditor.InitialText &&
                    snapshot.GetProperty("selectionStart").GetInt32() == WireEditor.InitialText.Length &&
                    snapshot.GetProperty("selectionLength").GetInt32() == 0 &&
                    !snapshot.TryGetProperty("Session", out _) && !snapshot.TryGetProperty("target", out _) &&
                    !begun.Raw.Contains(WireEditor.NativeIdentity, StringComparison.Ordinal),
                    "real textBegin ACK uses lower-camel fields, preserves Chinese emoji and hides native identity");

                await Send(socket, new { id = Guid.NewGuid().ToString("D"), type = "textSync", session,
                    revision = 1, text = WireEditor.InitialText, selectionStart = 0,
                    selectionLength = WireEditor.InitialText.Length }, deadline.Token);
                var selected = await Receive(socket, deadline.Token);
                check(selected.Json.GetProperty("ok").GetBoolean() && editor.State.SelectionStart == 0 &&
                    editor.State.SelectionLength == WireEditor.InitialText.Length &&
                    selected.Json.GetProperty("liveText").GetProperty("revision").GetInt32() == 1,
                    "real textSync selects all and acknowledges the new revision");

                var deletion = new { id = Guid.NewGuid().ToString("D"), type = "textSync", session,
                    revision = 2, text = "", selectionStart = 0, selectionLength = 0 };
                await Send(socket, deletion, deadline.Token);
                var deleted = await Receive(socket, deadline.Token);
                var writes = editor.Writes;
                await Send(socket, deletion, deadline.Token);
                var duplicate = await Receive(socket, deadline.Token);
                check(deleted.Json.GetProperty("ok").GetBoolean() && editor.State.Text == "" &&
                    deleted.Json.GetProperty("liveText").GetProperty("text").GetString() == "" &&
                    duplicate.Raw == deleted.Raw && editor.Writes == writes && writes == 2,
                    "real wire empty deletion is applied once and duplicate returns the identical ACK");

                var maximumText = new string('中', Protocol.MaximumTextUnits);
                var maximumRequestBytes = await Send(socket, new { id = Guid.NewGuid().ToString("D"),
                    type = "textSync", session, revision = 3, text = maximumText,
                    selectionStart = maximumText.Length, selectionLength = 0 }, deadline.Token);
                var maximum = await Receive(socket, deadline.Token);
                check(maximum.Json.GetProperty("ok").GetBoolean() &&
                    maximum.Json.GetProperty("liveText").GetProperty("text").GetString() == maximumText &&
                    editor.State.Text == maximumText && maximumRequestBytes is > 48_000 and < Protocol.MaximumFrameBytes &&
                    maximum.Bytes is > 48_000 and < Protocol.MaximumFrameBytes,
                    "real 16000-character Chinese request and ACK both fit the 64 KiB wire limit without truncation");

                editor.Unsupported = true;
                var unsupportedId = Guid.NewGuid().ToString("D");
                await Send(socket, new { id = unsupportedId, type = "textBegin" }, deadline.Token);
                var unsupported = await Receive(socket, deadline.Token);
                check(!unsupported.Json.GetProperty("ok").GetBoolean() &&
                    unsupported.Json.GetProperty("id").GetString() == unsupportedId &&
                    unsupported.Json.GetProperty("error").GetString()!.StartsWith("live_text_unsupported:", StringComparison.Ordinal) &&
                    !unsupported.Json.TryGetProperty("liveText", out _),
                    "native unsupported error code survives the real receiver ACK serializer");

                await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Fixture complete.", deadline.Token);
                await editor.Disposed.Task.WaitAsync(deadline.Token);
                check(socket.State == WebSocketState.Closed && input.Applied == 0,
                    "real socket close disposes the live editor without injecting desktop events");
            }
            finally
            {
                using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                await app.StopAsync(stop.Token);
            }
            check(input.Releases > 0, "real receiver shutdown releases only the injected recording backend");
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, true);
        }
        check(!Directory.Exists(directory), "wire fixture removes its dedicated temporary credentials");
    }

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
    private static async Task<int> Send(ClientWebSocket socket, object value, CancellationToken cancellation)
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(value, JsonOptions);
        await socket.SendAsync(bytes, WebSocketMessageType.Text, true, cancellation);
        return bytes.Length;
    }
    private static async Task<(JsonElement Json, int Bytes, string Raw)> Receive(ClientWebSocket socket, CancellationToken cancellation)
    {
        var bytes = new byte[Protocol.MaximumFrameBytes + 1];
        var count = 0;
        WebSocketReceiveResult received;
        do
        {
            received = await socket.ReceiveAsync(new ArraySegment<byte>(bytes, count, bytes.Length - count), cancellation);
            if (received.MessageType != WebSocketMessageType.Text)
                throw new InvalidOperationException("Live wire fixture expected a text response.");
            count += received.Count;
            if (count > Protocol.MaximumFrameBytes)
                throw new InvalidOperationException("Live wire response exceeded 64 KiB.");
        } while (!received.EndOfMessage);
        using var document = JsonDocument.Parse(bytes.AsMemory(0, count));
        return (document.RootElement.Clone(), count, Encoding.UTF8.GetString(bytes, 0, count));
    }

    private sealed class WireInput : IInputInjector
    {
        public int Applied, Releases;
        public bool Available => true;
        public void Apply(ActionMessage action) => Interlocked.Increment(ref Applied);
        public void ReleaseAll() => Interlocked.Increment(ref Releases);
    }
    private sealed class WireEditor : ILiveTextEditor
    {
        internal const string InitialText = "已有中文 🛋️\n第二行";
        internal const string NativeIdentity = "native-only-live-wire-fixture";
        internal TextEditorSnapshot State = new(NativeIdentity, InitialText, InitialText.Length, 0);
        internal bool Unsupported;
        internal int Writes;
        internal readonly TaskCompletionSource Disposed = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TextEditorSnapshot Read()
        {
            if (Unsupported) throw new InputInjectionException("live_text_unsupported: Fixture target is unsupported.");
            return State;
        }
        public TextEditorSnapshot Replace(TextEditorSnapshot expected, string text, int selectionStart, int selectionLength)
        {
            if (State != expected) throw new InputInjectionException("live_text_conflict: Fixture state changed.");
            Writes++;
            return State = State with { Text = text, SelectionStart = selectionStart, SelectionLength = selectionLength };
        }
        public void Dispose() => Disposed.TrySetResult();
    }
}
