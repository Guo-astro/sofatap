using SofaTap.Desktop;

internal static class StartupChecks
{
    internal static int Run()
    {
        var count = 0;
        void Check(bool condition, string name) { if (!condition) throw new Exception(name); count++; }
        var store = new FakeStore();
        var registration = new StartupRegistration(store);
        Check(registration.Initialize() && store.Preference == true && store.ShortcutExists, "First normal launch registers startup once");
        Check(!registration.SetEnabled(false) && store.Preference == false && !store.ShortcutExists, "Explicit opt-out removes startup entry");
        Check(!registration.Initialize() && store.Ensures == 1, "Relaunch preserves explicit opt-out");
        Check(registration.SetEnabled(true) && store.ShortcutExists, "Explicit re-enable restores shortcut");
        store.ShortcutExists = false;
        Check(!registration.Initialize() && store.Preference == false && !store.ShortcutExists, "Manual shortcut removal is an opt-out");
        var legacy = new FakeStore { ShortcutExists = true, DisabledByWindows = true };
        Check(new StartupRegistration(legacy).Initialize() && legacy.DisabledByWindows, "Legacy shortcut keeps Windows disabled approval unchanged");
        var failed = new FakeStore { FailEnsure = true };
        try { new StartupRegistration(failed).Initialize(); throw new Exception("Failure must surface"); }
        catch (IOException) { count++; }
        Check(failed.Preference is null, "Failed registration does not mark startup as configured");
        var disabled = new FakeStore { Preference = false };
        Check(!new StartupRegistration(disabled).Initialize() && disabled.Ensures == 0, "Disabled setting never invokes registration");
        Check(ReceiverLaunchOptions.Parse([]) is { ManagesStartup: true, Startup: false }, "Normal launch permits first-use startup setup");
        Check(ReceiverLaunchOptions.Parse(["--startup"]) is { Startup: true, BackendArguments.Length: 0 }, "Startup marker is not forwarded to backend");
        Check(ReceiverLaunchOptions.Parse(["--dry-run"]) is { ManagesStartup: false, BackendArguments: ["--dry-run"] }, "Dry-run cannot change login items");
        Check(ReceiverLaunchOptions.Parse(["--startup", "--dry-run"]) is null, "Conflicting launch modes rejected");
        Check(ReceiverLaunchOptions.Parse(["--startup", "--startup"]) is null, "Duplicate startup markers rejected");
        Check(ReceiverLaunchOptions.Parse(["--unknown"]) is null, "Unknown launch option rejected");
        if (OperatingSystem.IsWindows())
        {
            var temporary = Path.Combine(Path.GetTempPath(), "sofatap-startup-test-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(temporary);
            try
            {
                var executable = Path.Combine(temporary, "测试 folder", "SofaTap.exe");
                var shortcut = Path.Combine(temporary, "fake Startup", "SofaTap.lnk");
                var preference = Path.Combine(temporary, "fake LocalAppData", "desktop-startup.json");
                var realStore = new WindowsStartupStore(executable, shortcut, preference);
                var realRegistration = new StartupRegistration(realStore);
                Check(realRegistration.Initialize() && File.Exists(shortcut), "Windows creates a real shortcut in isolated temporary folder");
                var bytes = File.ReadAllBytes(shortcut);
                Check(realRegistration.Initialize() && bytes.SequenceEqual(File.ReadAllBytes(shortcut)), "Unchanged existing shortcut is not rewritten");
                Check(realStore.ReadPreference() == true, "Startup preference persists atomically");
                Check(!realRegistration.SetEnabled(false) && !File.Exists(shortcut) && realStore.ReadPreference() == false, "Opt-out persists and removes only isolated shortcut");
                Check(!new StartupRegistration(new WindowsStartupStore(executable, shortcut, preference)).Initialize(), "Restart reads persisted opt-out");
                File.WriteAllText(preference, "broken json");
                try { realRegistration.Initialize(); throw new Exception("Corrupt preference should fail closed"); }
                catch (System.Text.Json.JsonException) { count++; }
                Check(!File.Exists(shortcut), "Corrupt preferences do not silently re-enable login startup");
                var foreign = new WindowsStartupStore(Path.Combine(temporary, "Other.exe"), shortcut, preference);
                foreign.EnsureShortcut();
                var foreignBytes = File.ReadAllBytes(shortcut);
                try { realStore.EnsureShortcut(); throw new Exception("Foreign shortcut must not be overwritten"); }
                catch (IOException) { count++; }
                try { realStore.RemoveShortcut(); throw new Exception("Foreign shortcut must not be removed"); }
                catch (IOException) { count++; }
                Check(foreignBytes.SequenceEqual(File.ReadAllBytes(shortcut)), "Foreign shortcut preserved on enable and disable");
            }
            finally { Directory.Delete(temporary, recursive: true); }
        }
        return count;
    }

    private sealed class FakeStore : IStartupStore
    {
        internal bool? Preference;
        internal int Ensures;
        internal bool FailEnsure;
        internal bool DisabledByWindows;
        public bool ShortcutExists { get; set; }
        public bool? ReadPreference() => Preference;
        public void WritePreference(bool enabled) => Preference = enabled;
        public void EnsureShortcut() { if (FailEnsure) throw new IOException("Synthetic failure"); Ensures++; ShortcutExists = true; }
        public void RemoveShortcut() => ShortcutExists = false;
    }
}
