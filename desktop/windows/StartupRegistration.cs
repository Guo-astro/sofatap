namespace SofaTap.Desktop;

internal interface IStartupStore
{
    bool? ReadPreference();
    void WritePreference(bool enabled);
    bool ShortcutExists { get; }
    void EnsureShortcut();
    void RemoveShortcut();
}

// The preference distinguishes the first normal launch from a later removal.
// A missing shortcut after setup is an opt-out, not an invitation to recreate it.
internal sealed class StartupRegistration(IStartupStore store)
{
    internal bool Initialize()
    {
        var preference = store.ReadPreference();
        if (preference == false) return false;
        if (preference == true && !store.ShortcutExists)
        {
            store.WritePreference(false);
            return false;
        }
        store.EnsureShortcut();
        store.WritePreference(true);
        return true;
    }

    internal static bool IsRecoverableError(Exception error) => error is IOException or UnauthorizedAccessException
        or System.Text.Json.JsonException or InvalidOperationException or KeyNotFoundException
        or System.Runtime.InteropServices.COMException or ArgumentException;

    internal bool SetEnabled(bool enabled)
    {
        if (enabled) store.EnsureShortcut();
        else store.RemoveShortcut();
        store.WritePreference(enabled);
        return enabled;
    }
}

internal sealed record ReceiverLaunchOptions(bool DryRun, bool Startup, bool? StartupPreference = null)
{
    internal bool ManagesStartup => !DryRun && StartupPreference is null;
    internal string[] BackendArguments => DryRun ? ["--dry-run"] : [];
    internal static ReceiverLaunchOptions? Parse(string[] arguments)
    {
        if (arguments.Any(argument => argument is not ("--dry-run" or "--startup" or "--enable-autostart" or "--disable-autostart")) ||
            arguments.Distinct().Count() != arguments.Length || arguments.Length > 1) return null;
        return new(arguments.Contains("--dry-run"), arguments.Contains("--startup"),
            arguments.Contains("--enable-autostart") ? true : arguments.Contains("--disable-autostart") ? false : null);
    }
}
