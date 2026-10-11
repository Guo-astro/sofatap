using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace SofaTap.Desktop;

internal sealed class BackendProcess : IDisposable
{
    private readonly SemaphoreSlim _writer = new(1, 1);
    private readonly object _shutdown = new();
    private readonly CancellationTokenSource _readLifetime = new();
    private Process? _process;
    private Task? _stopTask;
    private bool _stopping;
    private bool _disposed;
    internal event Action<ReceiverState>? StateReceived;
    internal event Action? Failed;

    internal void Start(string executable, IEnumerable<string> arguments)
    {
        if (_process is not null) throw new InvalidOperationException("Receiver already started.");
        var info = new ProcessStartInfo(executable)
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8, WorkingDirectory = Path.GetDirectoryName(executable)!
        };
        info.ArgumentList.Add("--native-ui");
        foreach (var argument in arguments) info.ArgumentList.Add(argument);
        _process = Process.Start(info) ?? throw new IOException("Receiver did not start.");
        _process.StandardInput.AutoFlush = true;
        _ = ReadStatesAsync(_process);
        _ = DrainErrorsAsync(_process);
    }

    private async Task ReadStatesAsync(Process process)
    {
        try
        {
            var frame = new StringBuilder();
            var buffer = new char[4096];
            int count;
            while ((count = await process.StandardOutput.ReadAsync(buffer, _readLifetime.Token)) > 0)
            {
                for (var index = 0; index < count; index++)
                {
                    var character = buffer[index];
                    if (character == '\n')
                    {
                        var state = NativeProtocol.Parse(frame.ToString());
                        frame.Clear();
                        if (!_stopping) StateReceived?.Invoke(state);
                    }
                    else
                    {
                        if (frame.Length >= NativeProtocol.MaximumLineLength)
                            throw new InvalidDataException("Receiver state is too large.");
                        frame.Append(character);
                    }
                }
            }
        }
        catch (Exception error) when (error is IOException or JsonException or InvalidDataException or InvalidOperationException
            or KeyNotFoundException or FormatException or OperationCanceledException) { }
        finally
        {
            if (!_stopping)
            {
                Failed?.Invoke();
                try { await StopAsync(); }
                catch (Exception error) when (error is IOException or InvalidOperationException or System.ComponentModel.Win32Exception) { }
            }
        }
    }

    private async Task DrainErrorsAsync(Process process)
    {
        // Drain diagnostics to prevent a pipe deadlock; never mirror raw output to logs/UI.
        var buffer = new char[2048];
        try { while (await process.StandardError.ReadAsync(buffer, _readLifetime.Token) > 0) { } }
        catch (Exception error) when (error is IOException or ObjectDisposedException or OperationCanceledException) { }
    }

    internal async Task SendAsync(string type, CancellationToken cancellation = default)
    {
        if (type is not ("refresh" or "requestAccess" or "quit")) throw new ArgumentException("Unknown UI command.");
        await _writer.WaitAsync(cancellation);
        try
        {
            if (_stopping && type != "quit") throw new IOException("Receiver is stopping.");
            if (_process is null || _process.HasExited) throw new IOException("Receiver is not running.");
            await _process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(new { type }).AsMemory(), cancellation);
        }
        finally { _writer.Release(); }
    }

    internal Task StopAsync()
    {
        _stopping = true;
        lock (_shutdown)
        {
            // Concurrent callers share one bounded shutdown; a failure remains retryable.
            if (_stopTask is null || _stopTask.IsFaulted) _stopTask = StopOwnedAsync();
            return _stopTask;
        }
    }

    private async Task StopOwnedAsync()
    {
        var process = _process;
        if (process is null || process.HasExited) return;
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        try
        {
            try { await SendAsync("quit", deadline.Token).WaitAsync(deadline.Token); }
            catch (Exception error) when (error is IOException or InvalidOperationException or ObjectDisposedException) { }
            await process.WaitForExitAsync(deadline.Token);
        }
        catch (OperationCanceledException) when (deadline.IsCancellationRequested)
        {
            // The deadline includes acquiring the writer and flushing quit, not just process exit.
            // Only the child created by this window may be stopped on timeout.
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(2)); }
            catch (TimeoutException) { throw new IOException("Receiver did not exit after termination."); }
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _stopping = true;
        _readLifetime.Cancel();
        _process?.Dispose();
        _readLifetime.Dispose();
        // A pending write may be completing during window disposal.
    }
}
