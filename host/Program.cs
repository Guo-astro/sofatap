using SofaTap;

if (args.Contains("--help", StringComparer.Ordinal))
{
    Console.WriteLine("Sofa Tap receiver\n  --dry-run             Validate transport without injecting input\n  --no-browser          Do not open local pairing dashboard\n  --data-dir <path>     Store pairing credentials in a separate profile\n  --dashboard-port <n>  Local-only dashboard (default 53318)\n  --port <n>            TLS control endpoint (default 53319)");
    return;
}
try
{
    string? Value(string flag)
    {
        var index = Array.IndexOf(args, flag);
        if (index < 0) return null;
        if (index + 1 >= args.Length || args[index + 1].StartsWith("--", StringComparison.Ordinal)) throw new ArgumentException($"Missing value for {flag}.");
        return args[index + 1];
    }
    int Port(string flag, int fallback)
    {
        var value = Value(flag);
        if (value is null) return fallback;
        if (!int.TryParse(value, out var port) || port is < 1 or > 65535) throw new ArgumentException($"Invalid port for {flag}.");
        return port;
    }
    var dryRun = args.Contains("--dry-run", StringComparer.Ordinal);
    if (!OperatingSystem.IsWindows() && !dryRun) throw new InvalidOperationException("Windows input requires Windows. Use --dry-run for transport tests on this operating system.");
    var options = new ReceiverOptions(dryRun, Value("--data-dir") ?? Credentials.DefaultDirectory,
        Port("--dashboard-port", 53318), Port("--port", Port("--control-port", 53319)), !args.Contains("--no-browser", StringComparer.Ordinal));
    if (options.ControlPort == options.DashboardPort) throw new ArgumentException("Dashboard and control ports must be different.");
    using var credentials = Credentials.LoadOrCreate(Path.GetFullPath(options.DataDirectory));
    IInputInjector input = dryRun ? new DryRunInput() : new WindowsInput();
    var server = new ReceiverServer(options, credentials, input);
    await using var app = server.Build();
    Console.WriteLine($"Sofa Tap {(dryRun ? "DRY RUN: input disabled" : "Windows receiver")}. Pair at http://localhost:{options.DashboardPort}/ on this PC. Press Ctrl+C to stop.");
    try { await app.RunAsync(); }
    finally { input.ReleaseAll(); }
}
catch (Exception error) when (error is ArgumentException or InvalidOperationException or IOException or FormatException or System.Text.Json.JsonException or System.Security.Cryptography.CryptographicException)
{
    // Never dump request bodies, pairing tokens, certificate bytes, or raw framework exceptions.
    Console.Error.WriteLine(error is ArgumentException or InvalidOperationException ? error.Message : "Sofa Tap could not read its local profile or open its ports. Check file permissions and whether another receiver is running.");
    Environment.ExitCode = 1;
}
