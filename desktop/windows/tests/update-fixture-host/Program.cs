using System.Text.Json;

// CI-only inert stand-in for the owned backend. It cannot bind ports, pair a
// device, inspect a desktop or send input. Production host code is not linked.
if (!OperatingSystem.IsWindows() || Environment.GetEnvironmentVariable("GITHUB_ACTIONS") != "true" ||
    Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT") != "github-hosted" || args is not ["--native-ui"])
    return 90;
var root = AppContext.BaseDirectory;
if (!File.Exists(Path.Combine(root, "sofatap-ci-owned-install"))) return 91;
var mode = File.ReadAllText(Path.Combine(root, "fixture-host-mode.txt")).Trim();
if (mode == "fail") { Console.WriteLine("deliberately invalid CI state"); return 17; }
if (mode != "ready") return 92;
File.WriteAllText(Path.Combine(root, "fixture-host-started.json"), JsonSerializer.Serialize(new { process = Environment.ProcessId }));
Console.WriteLine("{\"type\":\"state\",\"name\":\"Updater CI fixture\",\"platform\":\"windows\",\"inputStatus\":\"ready\",\"dryRun\":true,\"connected\":false,\"pairings\":[]}");
Console.Out.Flush();
using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(3));
try
{
    while (await Console.In.ReadLineAsync(deadline.Token) is { } line)
    {
        using var command = JsonDocument.Parse(line);
        if (command.RootElement.GetProperty("type").GetString() == "quit") return 0;
    }
}
catch (OperationCanceledException) { }
return 0;
