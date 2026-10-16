namespace SofaTap.Desktop;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        var options = ReceiverLaunchOptions.Parse(args);
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
        using var window = new PairingWindow(options);
        _ = window.Handle; // Receive a concurrent manual reopen before Application.Run shows it.
        var registration = ThreadPool.RegisterWaitForSingleObject(showWindow, (_, _) => window.RequestShow(), null, Timeout.Infinite, executeOnlyOnce: false);
        try { Application.Run(window); }
        finally { registration.Unregister(null); }
        return 0;
    }
}
