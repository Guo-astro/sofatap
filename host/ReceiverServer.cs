using System.Diagnostics;
using System.Net;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using QRCoder;

namespace SofaTap;

public sealed record ReceiverOptions(bool DryRun, string DataDirectory, int DashboardPort = 53318, int ControlPort = 53319, bool OpenBrowser = true);

public sealed class ReceiverServer(ReceiverOptions options, Credentials credentials, IInputInjector input)
{
    private readonly SemaphoreSlim _controller = new(1, 1);
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web) { DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull };
    private readonly byte[] _token = Encoding.ASCII.GetBytes(credentials.Token);
    public WebApplication Build()
    {
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { Args = [], ContentRootPath = AppContext.BaseDirectory });
        builder.Logging.ClearProviders();
        builder.Logging.AddSimpleConsole(config => config.SingleLine = true);
        builder.Logging.SetMinimumLevel(LogLevel.Warning);
        builder.WebHost.ConfigureKestrel(server =>
        {
            server.AddServerHeader = false;
            server.Limits.MaxRequestBodySize = 0;
            server.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(10);
            server.Limits.KeepAliveTimeout = TimeSpan.FromSeconds(30);
            server.ListenLocalhost(options.DashboardPort, listen => listen.Protocols = HttpProtocols.Http1);
            server.ListenAnyIP(options.ControlPort, listen => { listen.Protocols = HttpProtocols.Http1; listen.UseHttps(credentials.Certificate); });
        });
        var app = builder.Build();
        app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(10) });
        app.Run(HandleRequest);
        app.Lifetime.ApplicationStopping.Register(input.ReleaseAll);
        if (options.OpenBrowser && OperatingSystem.IsWindows())
            app.Lifetime.ApplicationStarted.Register(() =>
            {
                try { Process.Start(new ProcessStartInfo($"http://localhost:{options.DashboardPort}/") { UseShellExecute = true }); }
                catch { Console.WriteLine($"Open http://localhost:{options.DashboardPort}/ on this PC to pair."); }
            });
        return app;
    }
    private async Task HandleRequest(HttpContext context)
    {
        context.Response.Headers.CacheControl = "no-store";
        context.Response.Headers["X-Content-Type-Options"] = "nosniff";
        context.Response.Headers["Referrer-Policy"] = "no-referrer";
        if (context.Connection.LocalPort == options.DashboardPort)
        {
            if (!IsLocalDashboardRequest(context)) { context.Response.StatusCode = 403; return; }
            context.Response.Headers.ContentSecurityPolicy = "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'";
            if (context.Request.Method != "GET") { context.Response.StatusCode = 405; return; }
            if (context.Request.Path == "/")
            {
                context.Response.ContentType = "text/html; charset=utf-8";
                await context.Response.WriteAsync(DashboardHtml()); return;
            }
            if (context.Request.Path == "/qr.svg")
            {
                var host = context.Request.Query["host"].ToString();
                if (!LocalAddresses().Contains(host, StringComparer.Ordinal)) { context.Response.StatusCode = 400; return; }
                using var generator = new QRCodeGenerator();
                using var data = generator.CreateQrCode(PairingUrl(host), QRCodeGenerator.ECCLevel.Q);
                using var code = new SvgQRCode(data);
                context.Response.ContentType = "image/svg+xml";
                await context.Response.WriteAsync(code.GetGraphic(6)); return;
            }
            context.Response.StatusCode = 404; return;
        }
        if (context.Request.Path != "/control" || context.Request.Method != "GET") { context.Response.StatusCode = 404; return; }
        // Native iOS has no Origin. Reject all browser-originated WebSocket requests, including Origin: null.
        if (context.Request.Headers.ContainsKey("Origin")) { context.Response.StatusCode = 403; return; }
        if (!Authorized(context.Request)) { context.Response.StatusCode = 401; return; }
        if (!context.WebSockets.IsWebSocketRequest) { context.Response.StatusCode = 400; return; }
        if (!await _controller.WaitAsync(0, context.RequestAborted)) { context.Response.StatusCode = 409; return; }
        try
        {
            using var socket = await context.WebSockets.AcceptWebSocketAsync();
            await RunController(socket, context.RequestAborted);
        }
        catch (OperationCanceledException) { }
        catch (WebSocketException) { }
        finally { input.ReleaseAll(); _controller.Release(); }
    }
    private bool IsLocalDashboardRequest(HttpContext context)
    {
        var address = context.Connection.RemoteIpAddress;
        if (address is null || !IPAddress.IsLoopback(address)) return false;
        var host = context.Request.Host;
        if (host.Port != options.DashboardPort || host.Host is not ("localhost" or "127.0.0.1" or "[::1]" or "::1")) return false;
        if (context.Request.Headers.TryGetValue("Origin", out var origins))
        {
            if (origins.Count != 1 || !Uri.TryCreate(origins[0], UriKind.Absolute, out var origin) || origin.Scheme != "http"
                || origin.Port != options.DashboardPort || origin.AbsolutePath != "/" || origin.UserInfo.Length != 0
                || origin.Host is not ("localhost" or "127.0.0.1" or "[::1]" or "::1")) return false;
        }
        return true;
    }
    private bool Authorized(HttpRequest request)
    {
        if (!request.Headers.TryGetValue("Authorization", out var header) || header.Count != 1) return false;
        var authorization = header[0];
        if (authorization is null || authorization.Length != 7 + _token.Length || !authorization.StartsWith("Bearer ", StringComparison.Ordinal)) return false;
        var candidate = Encoding.ASCII.GetBytes(authorization[7..]);
        return CryptographicOperations.FixedTimeEquals(candidate, _token);
    }
    private async Task RunController(WebSocket socket, CancellationToken requestAborted)
    {
        using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(requestAborted);
        await Send(socket, new { type = "hello", version = 1, name = Environment.MachineName, inputAvailable = input.Available }, lifetime.Token);
        var session = new ActionSession(input);
        var buffer = new byte[Protocol.MaximumFrameBytes + 1];
        while (socket.State == WebSocketState.Open && !lifetime.IsCancellationRequested)
        {
            var offset = 0;
            using var idle = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
            // The whole next message, including its fragments, must arrive within the idle budget.
            idle.CancelAfter(TimeSpan.FromSeconds(20));
            try
            {
                WebSocketReceiveResult received;
                do
                {
                    received = await socket.ReceiveAsync(new ArraySegment<byte>(buffer, offset, buffer.Length - offset), idle.Token);
                    if (received.MessageType == WebSocketMessageType.Close) { await Close(socket, WebSocketCloseStatus.NormalClosure, "Controller closed."); return; }
                    if (received.MessageType != WebSocketMessageType.Text) { await Close(socket, WebSocketCloseStatus.InvalidMessageType, "Text JSON required."); return; }
                    offset += received.Count;
                    if (offset > Protocol.MaximumFrameBytes) { await Close(socket, WebSocketCloseStatus.MessageTooBig, "Frame exceeds 64 KiB."); return; }
                } while (!received.EndOfMessage);
                var bytes = buffer.AsMemory(0, offset);
                ActionAck ack;
                try { ack = session.Execute(Protocol.Parse(bytes)); }
                catch (ProtocolException error)
                {
                    ack = ActionAck.Failure(Protocol.TryReadId(bytes), error.Message);
                    await Send(socket, ack, lifetime.Token);
                    if (error.Message.StartsWith("Session action limit", StringComparison.Ordinal)) { await Close(socket, WebSocketCloseStatus.PolicyViolation, "Reconnect required."); return; }
                    continue;
                }
                catch (JsonException) { ack = ActionAck.Failure("", "Malformed JSON."); }
                catch (InvalidOperationException) { ack = ActionAck.Failure(Protocol.TryReadId(bytes), "Invalid JSON string."); }
                await Send(socket, ack, lifetime.Token);
            }
            catch (OperationCanceledException) when (!lifetime.IsCancellationRequested)
            {
                input.ReleaseAll();
                await Close(socket, WebSocketCloseStatus.PolicyViolation, "Controller idle timeout.");
                return;
            }
        }
    }
    private static async Task Send(WebSocket socket, object message, CancellationToken cancellation)
    {
        using var bounded = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        bounded.CancelAfter(TimeSpan.FromSeconds(5));
        await socket.SendAsync(JsonSerializer.SerializeToUtf8Bytes(message, JsonOptions), WebSocketMessageType.Text, true, bounded.Token);
    }
    private static async Task Close(WebSocket socket, WebSocketCloseStatus status, string reason)
    {
        using var bounded = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        try { await socket.CloseOutputAsync(status, reason, bounded.Token); }
        catch (WebSocketException) { }
        catch (OperationCanceledException) { }
    }
    private string PairingUrl(string host) => $"sofatap://pair?host={Uri.EscapeDataString(host)}&port={options.ControlPort}&token={credentials.Token}&fingerprint={credentials.Fingerprint}";
    private string DashboardHtml()
    {
        var addresses = LocalAddresses();
        var cards = string.Join("", addresses.Select(address => $"<section data-pairing-uri=\"{HtmlEncoder.Default.Encode(PairingUrl(address))}\"><h2>{HtmlEncoder.Default.Encode(address)}</h2><img width='330' height='330' alt='私密 iPhone 配对二维码' src='/qr.svg?host={address}'/><p>iPhone → 配对电脑 → 扫描二维码</p><details><summary>无法扫码？复制配对链接</summary><p>仅发送到自己的 iPhone，在“粘贴配对链接”中打开。链接可控制这台电脑，请勿公开。</p><textarea readonly rows='5' spellcheck='false' aria-label='私密配对链接'>{HtmlEncoder.Default.Encode(PairingUrl(address))}</textarea></details></section>"));
        var status = options.DryRun ? "演练模式 · 不会操作电脑" : input.Available ? "已就绪 · 可以操作 Windows 桌面" : "请登录并解锁 Windows 桌面";
        return $$"""
            <!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
            <title>Sofa Tap · 配对 iPhone</title><style>
            body{background:#111b1a;color:#f0f6ed;font:17px system-ui,sans-serif;margin:0;padding:48px;line-height:1.5}main{max-width:1000px;margin:auto}h1{font-size:42px;margin:10px 0}h2{font-size:20px}small{color:#b6cec7}.status{color:#a7e3aa}.cards{display:flex;gap:24px;flex-wrap:wrap}section{background:#20312d;border-radius:20px;padding:24px;text-align:center;max-width:330px}details{text-align:left;max-width:330px;font-size:14px}summary{cursor:pointer}textarea{box-sizing:border-box;width:100%;background:#111b1a;color:#f0f6ed;border:1px solid #64877c;border-radius:8px;padding:10px;resize:vertical;font:12px ui-monospace,monospace}img{background:white;border-radius:10px;max-width:100%;height:auto}p{max-width:720px}code{font-size:15px}
            </style><main><small>SOFA TAP / 电脑接收端</small><h1>配对你的 iPhone</h1><p class="status">{{HtmlEncoder.Default.Encode(status)}}</p>
            <p>请让 iPhone 和电脑连接同一个家庭网络，再扫描电脑家庭网络地址下的二维码。若家庭网络地址改变，请重启 Sofa Tap 后重新扫码。二维码可授权操作电脑，请妥善保管。</p>
            <div class="cards">{{cards}}</div><p>操作电脑时请保持接收端运行。发送的文字会输入当前获得焦点的输入框。管理员程序和 Windows 安全桌面可能拒绝接收输入。</p>
            <p>超时或断开连接后，接收端会释放按住的鼠标按钮。如需撤销已配对的手机，请关闭 Sofa Tap，删除本机配对配置，再启动并扫描新的二维码。</p>
            <small>控制端口 {{options.ControlPort}} · 本机配对页端口 {{options.DashboardPort}} · iPhone 固定验证 TLS 证书 · 无云服务</small></main></html>
            """;
    }
    private string[] LocalAddresses()
    {
        var certificateAddresses = credentials.CertificateIPv4.ToHashSet(StringComparer.Ordinal);
        var addresses = NetworkAddresses.LocalIPv4().Where(certificateAddresses.Contains).ToArray();
        return addresses.Length > 0 ? addresses : ["127.0.0.1"];
    }
}
