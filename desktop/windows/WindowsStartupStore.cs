using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text.Json;

namespace SofaTap.Desktop;

[SupportedOSPlatform("windows")]
internal sealed class WindowsStartupStore : IStartupStore
{
    private readonly string _executable;
    private readonly string _shortcut;
    private readonly string _preference;

    internal WindowsStartupStore() : this(
        Environment.ProcessPath ?? throw new IOException("Executable path is unavailable."),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup, Environment.SpecialFolderOption.DoNotVerify), "SofaTap.lnk"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData, Environment.SpecialFolderOption.DoNotVerify), "SofaTap", "desktop-startup.json")) { }

    // Explicit paths are used by isolated tests; never point them at user Startup.
    internal WindowsStartupStore(string executable, string shortcut, string preference)
    {
        if (!Path.IsPathFullyQualified(executable) || !Path.IsPathFullyQualified(shortcut) || !Path.IsPathFullyQualified(preference))
            throw new IOException("Windows startup paths are unavailable.");
        _executable = executable;
        _shortcut = shortcut;
        _preference = preference;
    }

    public bool ShortcutExists => File.Exists(_shortcut);

    public bool? ReadPreference()
    {
        if (!File.Exists(_preference)) return null;
        using var json = JsonDocument.Parse(File.ReadAllText(_preference));
        return json.RootElement.GetProperty("enabled").GetBoolean();
    }

    public void WritePreference(bool enabled)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_preference)!);
        var temporary = _preference + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(new { enabled }));
            File.Move(temporary, _preference, overwrite: true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    public void EnsureShortcut()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_shortcut)!);
        WithShortcut(link =>
        {
            var existingTarget = (string)link.TargetPath;
            if (ShortcutExists) ValidateOwnership(existingTarget);
            var directory = Path.GetDirectoryName(_executable)!;
            if (ShortcutExists && string.Equals(existingTarget, _executable, StringComparison.OrdinalIgnoreCase) &&
                (string)link.Arguments == "--startup" && string.Equals((string)link.WorkingDirectory, directory, StringComparison.OrdinalIgnoreCase)) return;
            link.TargetPath = _executable;
            link.Arguments = "--startup";
            link.WorkingDirectory = directory;
            link.Description = "Sofatap iPhone remote receiver";
            link.IconLocation = _executable + ",0";
            link.Save();
            // Preserve this stable shortcut name and Windows' Startup Apps approval.
            // Never write StartupApproved or use another registration to evade a disable.
        });
    }

    private static void ValidateOwnership(string target)
    {
        if (!string.Equals(Path.GetFileName(target), "SofaTap.exe", StringComparison.OrdinalIgnoreCase))
            throw new IOException("The Sofatap startup shortcut points to another application.");
    }

    private void WithShortcut(Action<dynamic> action)
    {
        object? shell = null;
        object? shortcut = null;
        try
        {
            shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell") ?? throw new IOException("Windows shortcut support is unavailable."));
            shortcut = ((dynamic)shell!).CreateShortcut(_shortcut);
            action(shortcut);
        }
        finally
        {
            if (shortcut is not null) Marshal.FinalReleaseComObject(shortcut);
            if (shell is not null) Marshal.FinalReleaseComObject(shell);
        }
    }

    public void RemoveShortcut()
    {
        if (!File.Exists(_shortcut)) return;
        WithShortcut(link => ValidateOwnership((string)link.TargetPath));
        File.Delete(_shortcut);
    }
}
