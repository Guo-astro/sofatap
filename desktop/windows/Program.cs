namespace SofaTap.Desktop;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        // Internal update modes never initialize the receiver or send input.
        if (args.Length == 2 && args[0] == "--apply-update")
            return UpdateApplication.ApplyAsync(args[1]).GetAwaiter().GetResult();
        string? healthTicket = null;
        ReceiverLaunchOptions? options;
        if (args.Length == 2 && args[0] == "--complete-update")
        {
            try { options = UpdateApplication.HealthLaunch(args[1]); healthTicket = args[1]; }
            catch (Exception error) when (WindowsUpdates.IsRecoverable(error)) { return 1; }
        }
        else options = ReceiverLaunchOptions.Parse(args);
        if (options is null)
        {
            ApplicationConfiguration.Initialize();
            MessageBox.Show("此启动器仅支持 --dry-run 演练或 --startup 后台启动参数。", "Sofatap", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 1;
        }
        if (options.StartupPreference is bool enabled)
        {
            try
            {
                new StartupRegistration(new WindowsStartupStore()).SetEnabled(enabled);
                return 0;
            }
            catch (Exception error) when (StartupRegistration.IsRecoverableError(error)) { return 1; }
        }
        ApplicationConfiguration.Initialize();
        using var instance = new Mutex(true, @"Local\Chekusu.SofaTap.Receiver", out var created);
        using var showWindow = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\Chekusu.SofaTap.ShowWindow");
        if (!created)
        {
            // A login race must not open a window over the user's current work.
            if (!options.Startup) showWindow.Set();
            return 0;
        }
        if (options.ManagesStartup && healthTicket is null)
        {
            try
            {
                if (WindowsUpdates.ReadSettings() is { Automatic: true, PendingTicket: not null } && UpdateApplication.StartPrepared(options.Startup)) return 0;
            }
            catch (Exception error) when (WindowsUpdates.IsRecoverable(error))
            {
                try { WindowsUpdates.SaveSettings(WindowsUpdates.ReadSettings() with { PendingTicket = null, LastError = "自动更新尚未完成，现有版本继续可用。请重新检查更新。" }); }
                catch (Exception saveError) when (WindowsUpdates.IsRecoverable(saveError)) { }
            }
        }
        using var window = new PairingWindow(options, healthTicket);
        _ = window.Handle; // Receive a concurrent manual reopen before Application.Run shows it.
        var registration = ThreadPool.RegisterWaitForSingleObject(showWindow, (_, _) => window.RequestShow(), null, Timeout.Infinite, executeOnlyOnce: false);
        try { Application.Run(window); }
        finally { registration.Unregister(null); }
        return 0;
    }
}
