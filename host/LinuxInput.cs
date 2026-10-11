using System.Diagnostics;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace SofaTap;

// A private, owned worker uses Linux desktop APIs. No shell, TCP listener or command execution protocol.
public sealed class LinuxInput : IInputInjector, IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
    internal static readonly HashSet<string> StatusCodes = ["ready", "permission_required", "permission_pending", "permission_denied",
        "desktop_unavailable", "unsupported_session", "dependency_missing", "input_unavailable"];
    private readonly object _gate = new();
    private readonly TimeSpan _timeout;
    private Process? _worker;
    private string _status = "dependency_missing";
    private bool _disposed;

    public LinuxInput() : this(DefaultStartInfo(), TimeSpan.FromSeconds(5)) { }
    internal LinuxInput(ProcessStartInfo? start, TimeSpan timeout)
    {
        _timeout = timeout;
        if (start is null) return;
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        start.RedirectStandardInput = start.RedirectStandardOutput = start.RedirectStandardError = true;
        start.StandardInputEncoding = start.StandardOutputEncoding = new UTF8Encoding(false, true);
        try
        {
            _worker = Process.Start(start);
            if (_worker is null) return;
            _ = DrainDiagnostics(_worker.StandardError);
            Exchange("status");
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or IOException or InvalidOperationException or InputInjectionException)
        { if (_worker is not null) StopWorker(); }
    }
    private static ProcessStartInfo? DefaultStartInfo()
    {
        if (!OperatingSystem.IsLinux()) return null;
        var script = Path.Combine(AppContext.BaseDirectory, "linux", "input_worker.py");
        if (!File.Exists(script) || !File.Exists("/usr/bin/python3")) return null;
        var start = new ProcessStartInfo("/usr/bin/python3") { WorkingDirectory = Path.GetDirectoryName(script)! };
        foreach (var argument in new[] { "-E", "-s", "-B", "-u", script }) start.ArgumentList.Add(argument);
        return start;
    }
    public string StatusCode
    {
        get
        {
            lock (_gate)
            {
                if (_worker is not null && !_disposed)
                    try { Exchange("status"); } catch (InputInjectionException) { }
                return _status;
            }
        }
    }
    public bool Available => StatusCode == "ready";
    public void RequestAccess()
    {
        lock (_gate)
        {
            if (_worker is null || _disposed) return;
            try { Exchange("requestAccess"); } catch (InputInjectionException) { }
        }
    }
    public void Apply(ActionMessage action)
    {
        lock (_gate)
        {
            if (_worker is null || _disposed) throw new InputInjectionException("input_unavailable: Restart the Linux receiver and check its desktop status.");
            Exchange("apply", action);
        }
    }
    public void ReleaseAll()
    {
        lock (_gate)
        {
            if (_worker is null || _disposed) return;
            try { Exchange("releaseAll"); } catch (InputInjectionException) { }
        }
    }
    private void Exchange(string type, ActionMessage? action = null)
    {
        var id = Guid.NewGuid().ToString("D");
        var request = new Dictionary<string, object?> { ["id"] = id, ["type"] = type };
        if (action is not null) request["action"] = SerializeAction(action);
        var line = JsonSerializer.Serialize(request, JsonOptions);
        if (Encoding.UTF8.GetByteCount(line) > 131_072) throw new InputInjectionException("input_failed: Linux input request is too large.");
        WorkerReply reply;
        try
        {
            var budget = type == "apply" ? _timeout : TimeSpan.FromMilliseconds(Math.Min(_timeout.TotalMilliseconds, 2000));
            using var deadline = new CancellationTokenSource(budget);
            var worker = _worker ?? throw new IOException();
            worker.StandardInput.WriteLineAsync(line.AsMemory(), deadline.Token).GetAwaiter().GetResult();
            worker.StandardInput.FlushAsync(deadline.Token).GetAwaiter().GetResult();
            reply = ParseReply(ReadResponse(worker.StandardOutput, deadline.Token).GetAwaiter().GetResult(), id);
            if (type == "apply" && reply.Ok && reply.Status != "ready") throw new IOException("Worker confirmed input while unavailable.");
        }
        catch (Exception error) when (error is IOException or InvalidOperationException or OperationCanceledException or JsonException or DecoderFallbackException)
        {
            _status = "input_unavailable";
            StopWorker();
            throw new InputInjectionException("input_unknown: The Linux input worker stopped or did not confirm completion. Check the desktop before resending text; restart the receiver.");
        }
        _status = reply.Status;
        if (!reply.Ok) throw new InputInjectionException(ErrorMessage(reply.Error));
    }
    internal static Dictionary<string, object?> SerializeAction(ActionMessage action)
    {
        var value = new Dictionary<string, object?> { ["id"] = action.Id, ["type"] = action.Type };
        switch (action.Type)
        {
            case "move": case "scroll": value["dx"] = action.Dx; value["dy"] = action.Dy; break;
            case "button": value["button"] = action.Button; value["down"] = action.Down; break;
            case "click": value["button"] = action.Button; break;
            case "key": value["key"] = action.Key; value["modifiers"] = action.Modifiers; break;
            case "text": value["text"] = action.Text; break;
            default: throw new InputInjectionException("input_failed: Unsupported Linux action.");
        }
        return value;
    }
    internal sealed record WorkerReply(bool Ok, string Status, string? Error);
    internal static WorkerReply ParseReply(string line, string expectedId)
    {
        if (line.Length > 4096) throw new IOException("Oversized worker reply.");
        using var document = JsonDocument.Parse(line, new JsonDocumentOptions { MaxDepth = 4 });
        if (document.RootElement.ValueKind != JsonValueKind.Object) throw new IOException("Invalid worker reply.");
        var fields = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        foreach (var property in document.RootElement.EnumerateObject())
            if (!fields.TryAdd(property.Name, property.Value)) throw new IOException("Duplicate worker field.");
        if (fields.Count is < 3 or > 4 || fields.Keys.Any(key => key is not ("id" or "ok" or "status" or "error"))
            || !fields.TryGetValue("id", out var id) || id.ValueKind != JsonValueKind.String || id.GetString() != expectedId
            || !fields.TryGetValue("ok", out var ok) || ok.ValueKind is not (JsonValueKind.True or JsonValueKind.False)
            || !fields.TryGetValue("status", out var status) || status.ValueKind != JsonValueKind.String || !StatusCodes.Contains(status.GetString()!))
            throw new IOException("Invalid worker reply.");
        string? code = null;
        if (fields.TryGetValue("error", out var error))
        {
            if (error.ValueKind != JsonValueKind.String || error.GetString()!.Length > 64) throw new IOException("Invalid worker error.");
            code = error.GetString();
        }
        if (ok.GetBoolean() && code is not null || !ok.GetBoolean() && string.IsNullOrWhiteSpace(code)) throw new IOException("Inconsistent worker reply.");
        return new(ok.GetBoolean(), status.GetString()!, code);
    }
    private static string ErrorMessage(string? code) => code switch
    {
        "input_partial" => "input_partial: Linux may have entered only part of the input. Check the desktop before resending.",
        "input_busy" => "input_busy: Release the physical keyboard or mouse buttons before trying this action.",
        "text_too_long" => "input_failed: This Linux desktop needs a shorter text selection. No text was sent.",
        "invalid_request" or "unsupported_action" => "input_failed: Linux rejected the requested input before sending it.",
        "permission_required" or "permission_denied" or "permission_pending" => "input_unavailable: Allow desktop control in the Linux receiver's native permission window.",
        "dependency_missing" => "input_unavailable: Install the Linux desktop dependencies shown in the receiver instructions.",
        "unsupported_session" => "input_unavailable: This Linux session does not provide a supported remote desktop interface.",
        "desktop_unavailable" or "input_unavailable" => "input_unavailable: Linux desktop control is unavailable. Check the receiver status.",
        _ => "input_unknown: Linux did not confirm the requested input. Check the desktop before resending."
    };
    private static async Task<string> ReadResponse(StreamReader reader, CancellationToken cancellation)
    {
        var line = new StringBuilder();
        var buffer = new char[1];
        while (await reader.ReadAsync(buffer.AsMemory(), cancellation) != 0)
        {
            if (buffer[0] == '\n') return line.ToString();
            if (line.Length == 4096) throw new IOException("Oversized worker reply.");
            line.Append(buffer[0]);
        }
        throw new IOException("Worker pipe closed.");
    }
    private static async Task DrainDiagnostics(StreamReader reader)
    {
        try { var buffer = new char[4096]; while (await reader.ReadAsync(buffer) > 0) { } }
        catch (Exception error) when (error is IOException or ObjectDisposedException) { }
    }
    private void StopWorker()
    {
        var worker = _worker;
        _worker = null;
        if (worker is null) return;
        // Dispose the pipe itself: StreamWriter.Close can synchronously flush a
        // blocked request into a worker which has stopped reading.
        try { worker.StandardInput.BaseStream.Dispose(); }
        catch (Exception error) when (error is IOException or InvalidOperationException) { }
        try
        {
            if (!worker.WaitForExit(1000)) { worker.Kill(entireProcessTree: true); worker.WaitForExit(1000); }
        }
        catch (Exception error) when (error is IOException or InvalidOperationException or System.ComponentModel.Win32Exception) { }
        finally { worker.Dispose(); }
    }
    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            if (_worker is not null) try { Exchange("quit"); } catch (InputInjectionException) { }
            _disposed = true;
            _status = "input_unavailable";
            StopWorker();
        }
    }
}
