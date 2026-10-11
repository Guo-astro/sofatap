using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Sofatap.Login;

// Fixed binary protocol, no arbitrary username, command, executable or target desktop from the network.
internal sealed class PipeBroker(LoginConfig config, AttemptBroker broker) : BackgroundService
{
    private const uint Magic = 0x5346544C;
    private const string PipeName = @"\\.\pipe\Sofatap.Login.v1";
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var pipe = Create();
                await pipe.WaitForConnectionAsync(stoppingToken);
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken); timeout.CancelAfter(TimeSpan.FromSeconds(2));
                await Handle(pipe, timeout.Token);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch { broker.Invalidate(); await Task.Delay(250, stoppingToken); }
        }
    }
    private async Task Handle(NamedPipeServerStream pipe, CancellationToken cancellation)
    {
        var header = new byte[48]; await pipe.ReadExactlyAsync(header, cancellation);
        var magic = BitConverter.ToUInt32(header); var operation = BitConverter.ToUInt32(header, 4);
        var session = BitConverter.ToInt32(header, 8); var generation = new Guid(header.AsSpan(12, 16));
        var attempt = new Guid(header.AsSpan(28, 16)); var result = BitConverter.ToInt32(header, 44);
        var system = false;
        pipe.RunAsClient(() => { using var identity = WindowsIdentity.GetCurrent(true); system = identity?.User?.Value == "S-1-5-18"; });
        if (magic != Magic || !system || !NativeWindows.GetNamedPipeClientProcessId(pipe.SafePipeHandle.DangerousGetHandle(), out var pid)
            || !NativeWindows.IsConsoleLogonUI(pid, session)) throw new UnauthorizedAccessException();
        if (!config.IdentityCurrent()) { broker.Invalidate(); throw new UnauthorizedAccessException(); }
        if (operation == 2)
        {
            broker.Report(attempt, session, generation, result == 0);
            if (NativeWindows.ConsoleState() is { Locked: false } state && NativeWindows.ConsoleIsTarget(config.Capability.AccountSid)) broker.ObserveUnlocked(state.Session);
            await pipe.WriteAsync(new byte[4], cancellation); return;
        }
        if (operation != 1 || NativeWindows.ConsoleState() is not { Locked: true } locked || locked.Session != session)
        { await pipe.WriteAsync(new byte[4], cancellation); return; }
        broker.ProviderSeen(session, generation);
        using var delivery = broker.Take(session, generation);
        if (delivery is null) { await pipe.WriteAsync(new byte[4], cancellation); return; }
        var account = Encoding.Unicode.GetBytes(config.Capability.AccountName);
        var payload = new byte[28 + account.Length + delivery.Password.Bytes.Length];
        try
        {
            BitConverter.TryWriteBytes(payload.AsSpan(), 1u); delivery.AttemptId.TryWriteBytes(payload.AsSpan(4, 16));
            BitConverter.TryWriteBytes(payload.AsSpan(20), checked((ushort)(account.Length / 2)));
            BitConverter.TryWriteBytes(payload.AsSpan(22), checked((ushort)(delivery.Password.Bytes.Length / 2)));
            BitConverter.TryWriteBytes(payload.AsSpan(24), delivery.RemainingMilliseconds);
            account.CopyTo(payload, 28); delivery.Password.Bytes.CopyTo(payload, 28 + account.Length);
            await pipe.WriteAsync(payload, cancellation); await pipe.FlushAsync(cancellation);
        }
        finally { System.Security.Cryptography.CryptographicOperations.ZeroMemory(payload); }
    }
    [StructLayout(LayoutKind.Sequential)] private struct Attributes { public int Size; public IntPtr Descriptor; public int Inherit; }
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string text, uint revision, out IntPtr descriptor, IntPtr size);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern SafePipeHandle CreateNamedPipe(string name, uint openMode, uint pipeMode, uint instances, uint output, uint input, uint timeout, ref Attributes attributes);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);
    private static NamedPipeServerStream Create()
    {
        if (!ConvertStringSecurityDescriptorToSecurityDescriptor("D:P(A;;GA;;;SY)", 1, out var descriptor, IntPtr.Zero)) throw new IOException();
        try
        {
            var attributes = new Attributes { Size = Marshal.SizeOf<Attributes>(), Descriptor = descriptor };
            // Duplex + overlapped + FIRST_PIPE_INSTANCE; byte mode + REJECT_REMOTE_CLIENTS.
            var handle = CreateNamedPipe(PipeName, 3 | 0x40000000 | 0x00080000, 8, 1, 8192, 128, 0, ref attributes);
            if (handle.IsInvalid) { handle.Dispose(); throw new IOException(); }
            return new NamedPipeServerStream(PipeDirection.InOut, true, false, handle);
        }
        finally { LocalFree(descriptor); }
    }
}

internal sealed class SessionObserver(AttemptBroker broker, LoginConfig config) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken token)
    {
        var previousSession = -1;
        while (!token.IsCancellationRequested)
        {
            var state = NativeWindows.ConsoleState();
            if (state is null || !config.IdentityCurrent()) broker.Invalidate();
            else
            {
                if (previousSession != -1 && previousSession != state.Value.Session) broker.Invalidate();
                previousSession = state.Value.Session;
                if (!state.Value.Locked)
                {
                    if (NativeWindows.ConsoleIsTarget(config.Capability.AccountSid)) broker.ObserveUnlocked(state.Value.Session);
                    else broker.Invalidate();
                }
            }
            await Task.Delay(300, token);
        }
    }
}
