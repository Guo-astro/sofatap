namespace SofaTap.Desktop;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        var options = ReceiverLaunchOptions.Parse(args);
        if (options is null)
        {
            MessageBox.Show("此启动器仅支持 --dry-run 演练或 --startup 后台启动参数。", "Sofatap", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        using var instance = new Mutex(true, @"Local\Chekusu.SofaTap.Receiver", out var created);
        using var showWindow = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\Chekusu.SofaTap.ShowWindow");
        if (!created)
        {
            // A login race must not open a window over the user's current work.
            if (!options.Startup) showWindow.Set();
            return;
        }
        using var window = new PairingWindow(options);
        _ = window.Handle; // Receive a concurrent manual reopen before Application.Run shows it.
        var registration = ThreadPool.RegisterWaitForSingleObject(showWindow, (_, _) => window.RequestShow(), null, Timeout.Infinite, executeOnlyOnce: false);
        try { Application.Run(window); }
        finally { registration.Unregister(null); }
    }
}
