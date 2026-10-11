using System.Drawing.Imaging;
using QRCoder;
using SofaTap.Desktop;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("WinForms rendering requires Windows.");
        if (args.Length > 1) throw new ArgumentException("Pass only the screenshot output directory.");
        // Stable logical dimensions for CI. The production app remains PerMonitorV2.
        Application.SetHighDpiMode(HighDpiMode.DpiUnaware);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        var output = Path.GetFullPath(args.FirstOrDefault() ?? "artifacts/mint-calm");
        Directory.CreateDirectory(output);

        // An ordinary QR with a clearly non-pairing payload. No real token, identity or server exists.
        using var data = QRCodeGenerator.GenerateQrCode("SOFATAP UI PREVIEW - DEMO ONLY - NOT A PAIRING CODE. " + new string('.', 140), QRCodeGenerator.ECCLevel.Q);
        using var qr = new PngByteQRCode(data);
        var png = qr.GetGraphic(5);
        const string host = "192.0.2.17"; // RFC 5737 documentation range.
        var demoLink = $"sofatap://pair?host={host}&port=53319&token={new string('D', 43)}&fingerprint={new string('0', 64)}";
        var state = new ReceiverState("客厅电脑", "windows", "ready", false, false, [new PairingImage(host, png, demoLink)]);

        using (var window = OpenFixture(state, new Size(472, 730)))
        {
            Require(window.PreviewHasQr && window.PreviewCopyEnabled, "Ready fixture must have a QR and available Copy action.");
            Capture(window, Path.Combine(output, "windows-ready.png"));
            window.ShowPreviewFailure();
            Application.DoEvents();
            Require(!window.PreviewHasQr && !window.PreviewCopyEnabled, "A failure must clear the stale QR and disable Copy.");
            Capture(window, Path.Combine(output, "windows-failure.png"));
        }
        using (var window = OpenFixture(state with { InputStatus = "accessibility_required" }, new Size(472, 730)))
            Capture(window, Path.Combine(output, "windows-permission.png"));
        using (var window = OpenFixture(state with { Name = "客厅电脑 · Living Room Computer with a long device name" }, new Size(334, 510)))
        {
            Require(window.PreviewCanScroll, "A short, narrow window must keep overflow reachable by scrolling.");
            Require(!window.PreviewHasHorizontalScroll, "The minimum-width fixture must not need horizontal scrolling.");
            Capture(window, Path.Combine(output, "windows-narrow.png"));
            window.ScrollPreviewToBottom();
            Application.DoEvents();
            Capture(window, Path.Combine(output, "windows-narrow-scrolled.png"));
        }
        using (var window = OpenFixture(state with { Pairings = [new PairingImage(host, png)] }, new Size(472, 730)))
            Require(window.PreviewHasQr && !window.PreviewCopyEnabled, "QR-only snapshots must render with Copy disabled.");
        Console.WriteLine("Rendered five synthetic WinForms fixtures; no backend, listener, clipboard write or desktop input was started.");
    }

    private static PairingWindow OpenFixture(ReceiverState state, Size clientSize)
    {
        var window = new PairingWindow(state)
        {
            ShowInTaskbar = false, StartPosition = FormStartPosition.Manual,
            Location = new Point(-32000, -32000), ClientSize = clientSize
        };
        // Create actual native handles off-screen, without activation; Shown has no backend handler in fixture mode.
        window.Show();
        Application.DoEvents();
        window.PerformLayout();
        return window;
    }

    private static void Capture(PairingWindow window, string path)
    {
        using var bitmap = new Bitmap(window.Width, window.Height);
        window.DrawToBitmap(bitmap, new Rectangle(Point.Empty, bitmap.Size));
        bitmap.Save(path, ImageFormat.Png);
    }

    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
