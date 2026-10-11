namespace SofaTap.Desktop;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        if (args.Any(argument => argument != "--dry-run"))
        {
            MessageBox.Show("此启动器仅支持可选的 --dry-run 演练参数。", "Sofa Tap", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        using var instance = new Mutex(true, @"Local\Chekusu.SofaTap.Receiver", out var created);
        if (!created)
        {
            MessageBox.Show("Sofa Tap 已经打开。请切换到现有的 Sofa Tap 窗口。", "Sofa Tap", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        Application.Run(new PairingWindow(args));
    }
}
