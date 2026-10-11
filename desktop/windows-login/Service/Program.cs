using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using Sofatap.Login;

if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
if (args is ["--provision", var fingerprint, var profile])
{
    LoginConfig.Provision(fingerprint, profile);
    Console.WriteLine("Optional login enrollment created for this local account. No computer password was requested or stored.");
    return;
}
if (args.Length != 0) throw new ArgumentException("Unsupported service arguments.");
using (var identity = WindowsIdentity.GetCurrent())
    if (identity.User?.Value != "S-1-5-18") throw new UnauthorizedAccessException("Service must run as LocalSystem.");
var config = LoginConfig.Load();
if (!config.IdentityCurrent()) throw new InvalidDataException("Account identity changed; re-enroll explicitly.");
using var certificate = X509CertificateLoader.LoadPkcs12(Convert.FromBase64String(config.Pfx), null, X509KeyStorageFlags.EphemeralKeySet);
if (certificate.NotAfter.ToUniversalTime() <= DateTime.UtcNow || !certificate.HasPrivateKey) throw new InvalidDataException("Re-enrollment required.");
var builder = WebApplication.CreateBuilder(new WebApplicationOptions { Args = [], ContentRootPath = AppContext.BaseDirectory });
builder.Logging.ClearProviders();
builder.Host.UseWindowsService(options => options.ServiceName = LoginConfig.ServiceName);
builder.Services.AddSingleton(config);
builder.Services.AddSingleton(new AttemptBroker(config.Capability.AccountSid, config.Capability.DeviceId));
builder.Services.AddHostedService<PipeBroker>(); builder.Services.AddHostedService<SessionObserver>();
builder.WebHost.ConfigureKestrel(server =>
{
    server.AddServerHeader = false; server.Limits.MaxRequestBodySize = 16_384;
    server.Limits.MaxConcurrentConnections = 8; server.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(5);
    server.Limits.KeepAliveTimeout = TimeSpan.FromSeconds(5);
    server.ListenAnyIP(53320, listen => { listen.Protocols = Microsoft.AspNetCore.Server.Kestrel.Core.HttpProtocols.Http1; listen.UseHttps(certificate); });
});
var app = builder.Build();
var broker = app.Services.GetRequiredService<AttemptBroker>();
var expectedToken = Encoding.ASCII.GetBytes("Bearer " + config.Capability.Token);
app.Run(async context =>
{
    context.Response.Headers.CacheControl = "no-store"; context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    using var deadline = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted); deadline.CancelAfter(TimeSpan.FromSeconds(5));
    try
    {
        if (context.Request.Headers.ContainsKey("Origin") || !LocalAddress(context.Connection.RemoteIpAddress)
            || context.Request.Headers.Authorization.Count != 1
            || !CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(context.Request.Headers.Authorization.ToString()), expectedToken))
        { context.Response.StatusCode = 401; return; }
        var path = context.Request.Path.Value; var method = context.Request.Method;
        var state = NativeWindows.ConsoleState();
        if (!config.IdentityCurrent())
        { broker.Invalidate(); throw new LoginDeniedException("account_identity_changed"); }
        if (method == "GET" && path == "/v1/status")
        {
            await context.Response.WriteAsJsonAsync(new { version = 1, accountSid = config.Capability.AccountSid, deviceId = config.Capability.DeviceId,
                accountName = config.Capability.AccountName, machineName = config.MachineName,
                state = state is null ? "unavailable" : !state.Value.Locked ? "ready" : broker.ProviderReady(state.Value.Session) ? "locked" : "unavailable" }, deadline.Token); return;
        }
        if (method == "POST" && path == "/v1/challenge")
        {
            if (state is not { Locked: true } locked) throw new LoginDeniedException("desktop_not_locked");
            await context.Response.WriteAsJsonAsync(broker.Create(locked.Session), deadline.Token); return;
        }
        if (method == "POST" && path == "/v1/unlock")
        {
            if (state is not { Locked: true } locked) throw new LoginDeniedException("desktop_not_locked");
            if (context.Request.ContentType != "application/json") throw new LoginDeniedException("invalid_content_type");
            var body = new byte[16_385]; var count = 0;
            try
            {
                while (count < body.Length)
                {
                    var read = await context.Request.Body.ReadAsync(body.AsMemory(count), deadline.Token); if (read == 0) break; count += read;
                }
                if (count == body.Length) throw new LoginDeniedException("body_too_large");
                using var submission = Submission.Parse(body.AsSpan(0, count));
                broker.Submit(submission.Id, submission.Nonce, submission.Password, locked.Session);
                context.Response.StatusCode = 202;
                await context.Response.WriteAsJsonAsync(broker.Status(submission.Id), deadline.Token); return;
            }
            finally { CryptographicOperations.ZeroMemory(body); }
        }
        if (path?.StartsWith("/v1/attempt/", StringComparison.Ordinal) == true && Guid.TryParseExact(path[12..], "D", out var id))
        {
            if (method == "GET") { await context.Response.WriteAsJsonAsync(broker.Status(id), deadline.Token); return; }
            if (method == "DELETE") { await context.Response.WriteAsJsonAsync(broker.Cancel(id), deadline.Token); return; }
        }
        context.Response.StatusCode = 404;
    }
    catch (LoginDeniedException e)
    {
        context.Response.StatusCode = e.Message == "rate_limited" ? 429 : 409;
        await context.Response.WriteAsJsonAsync(new { error = e.Message }, context.RequestAborted);
    }
    catch (Exception e) when (e is JsonException or InvalidDataException or FormatException or OperationCanceledException or BadHttpRequestException)
    { if (!context.Response.HasStarted) context.Response.StatusCode = 400; }
});
await app.RunAsync();

static bool LocalAddress(IPAddress? ip)
{
    if (ip is null) return false; if (ip.IsIPv4MappedToIPv6) ip = ip.MapToIPv4(); if (IPAddress.IsLoopback(ip)) return true;
    var bytes = ip.GetAddressBytes();
    return bytes.Length == 4 ? bytes[0] == 10 || bytes[0] == 192 && bytes[1] == 168 || bytes[0] == 172 && bytes[1] is >= 16 and <= 31
        : bytes.Length == 16 && ((bytes[0] & 0xfe) == 0xfc || bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
}

internal sealed record Submission(Guid Id, string Nonce, SecretBytes Password) : IDisposable
{
    public void Dispose() => Password.Dispose();
    internal static Submission Parse(ReadOnlySpan<byte> bytes)
    {
        var reader = new Utf8JsonReader(bytes, new JsonReaderOptions { MaxDepth = 2 });
        string? id = null, nonce = null; SecretBytes? secret = null; var seen = new HashSet<string>();
        try
        {
            if (!reader.Read() || reader.TokenType != JsonTokenType.StartObject) throw new JsonException();
            while (reader.Read() && reader.TokenType != JsonTokenType.EndObject)
            {
                if (reader.TokenType != JsonTokenType.PropertyName) throw new JsonException();
                var name = reader.GetString()!;
                if (!seen.Add(name) || !reader.Read() || reader.TokenType != JsonTokenType.String) throw new JsonException();
                switch (name)
                {
                    case "attemptId": id = reader.GetString(); break;
                    case "nonce": nonce = reader.GetString(); break;
                    case "password":
                        var chars = new char[1025];
                        try
                        {
                            var length = reader.CopyString(chars);
                            if (length is < 1 or > 1024 || chars.AsSpan(0, length).Contains('\0')) throw new JsonException();
                            secret = new SecretBytes(Encoding.Unicode.GetBytes(chars, 0, length));
                        }
                        finally { CryptographicOperations.ZeroMemory(System.Runtime.InteropServices.MemoryMarshal.AsBytes(chars.AsSpan())); }
                        break;
                    default: throw new JsonException();
                }
            }
            if (reader.TokenType != JsonTokenType.EndObject || reader.Read() || !Guid.TryParseExact(id, "D", out var guid) || nonce?.Length != 43 || secret is null) throw new JsonException();
            return new(guid, nonce, secret);
        }
        catch { secret?.Dispose(); throw; }
    }
}
