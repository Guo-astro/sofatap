using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace SofaTap;

// An optional AT-SPI process is separate from both the input worker and its Wayland portal.
// Portal permission does not imply accessibility support or permission.
internal sealed class LinuxTextFocusProbe : ITextFocusProbe
{
    private Process? _worker;
    private bool _starting = true;

    internal LinuxTextFocusProbe()
    {
        var script = Path.Combine(AppContext.BaseDirectory, "linux", "text_focus_worker.py");
        if (!File.Exists(script) || !File.Exists("/usr/bin/python3")) return;
        var start = new ProcessStartInfo("/usr/bin/python3")
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = new UTF8Encoding(false, true)
        };
        foreach (var argument in new[] { "-E", "-s", "-B", "-u", script }) start.ArgumentList.Add(argument);
        try
        {
            _worker = Process.Start(start);
            if (_worker is not null) _ = Drain(_worker.StandardError);
        }
        catch (System.ComponentModel.Win32Exception) { }
    }

    public TextFocusSnapshot Read()
    {
        if (_worker is null) return new(TextFocusKind.Unknown);
        try
        {
            using var deadline = new CancellationTokenSource(_starting ? 3000 : 1000);
            _starting = false;
            return Parse(ReadBounded(_worker.StandardOutput, deadline.Token).GetAwaiter().GetResult());
        }
        catch (Exception error) when (error is IOException or InvalidOperationException or OperationCanceledException or JsonException)
        { Dispose(); return new(TextFocusKind.Unknown); }
    }

    internal static TextFocusSnapshot Parse(string line)
    {
        if (line.Length > 128) throw new IOException("Invalid focus metadata.");
        using var document = JsonDocument.Parse(line, new JsonDocumentOptions { MaxDepth = 2 });
        if (document.RootElement.ValueKind != JsonValueKind.Object) throw new IOException("Invalid focus metadata.");
        var fields = document.RootElement.EnumerateObject().ToArray();
        if (fields.Length != 2 || fields.Count(item => item.Name == "kind") != 1 || fields.Count(item => item.Name == "identity") != 1)
            throw new IOException("Invalid focus metadata.");
        var kind = document.RootElement.GetProperty("kind").GetString() switch
        {
            "unknown" => TextFocusKind.Unknown, "other" => TextFocusKind.Other,
            "editable" => TextFocusKind.Editable, "protected" => TextFocusKind.Protected,
            _ => throw new IOException("Invalid focus metadata.")
        };
        var identity = document.RootElement.GetProperty("identity").GetString();
        if (kind == TextFocusKind.Unknown ? identity is not null : identity is null || !Guid.TryParseExact(identity, "N", out _))
            throw new IOException("Invalid focus identity.");
        return new(kind, identity);
    }
    private static async Task<string> ReadBounded(StreamReader reader, CancellationToken cancellation)
    {
        var buffer = new char[1];
        var line = new StringBuilder();
        while (await reader.ReadAsync(buffer.AsMemory(), cancellation) > 0)
        {
            if (buffer[0] == '\n') return line.ToString();
            if (line.Length == 128) throw new IOException("Oversized focus metadata.");
            line.Append(buffer[0]);
        }
        throw new IOException("Focus worker closed.");
    }
    private static async Task Drain(StreamReader reader)
    {
        try { var buffer = new char[1024]; while (await reader.ReadAsync(buffer) > 0) { } }
        catch (Exception error) when (error is IOException or ObjectDisposedException) { }
    }
    public void Dispose()
    {
        var process = _worker; _worker = null;
        if (process is null) return;
        try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
        catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception) { }
        finally { process.Dispose(); }
    }
}
