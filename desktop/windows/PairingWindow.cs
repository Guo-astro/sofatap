namespace SofaTap.Desktop;

internal sealed class PairingWindow : Form
{
    private readonly BackendProcess _backend = new();
    private readonly string[] _arguments;
    private readonly Label _machine = new() { AutoSize = true, Dock = DockStyle.Fill, Text = "正在启动电脑接收端…" };
    private readonly Label _status = new() { AutoSize = true, Dock = DockStyle.Fill, Text = "正在准备配对", ForeColor = Color.FromArgb(25, 105, 72) };
    private readonly ComboBox _addresses = new() { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList, AccessibleName = "电脑局域网地址" };
    private readonly PictureBox _qr = new() { Dock = DockStyle.Fill, SizeMode = PictureBoxSizeMode.Zoom, BackColor = Color.White, AccessibleName = "iPhone 私密配对二维码" };
    private readonly Label _placeholder = new() { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter, Text = "正在生成二维码…", BackColor = Color.White };
    private readonly Button _refresh = new() { Text = "刷新", AutoSize = true, Enabled = false };
    private readonly Button _quit = new() { Text = "退出接收器", AutoSize = true };
    private PairingImage[] _pairings = [];
    private byte[]? _renderedPng;
    private bool _updating;
    private bool _stopping;
    private bool _allowClose;

    internal PairingWindow(string[] arguments)
    {
        _arguments = arguments;
        Text = "Sofa Tap";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(470, 700);
        MinimumSize = new Size(410, 640);
        Font = new Font("Segoe UI", 11);
        AutoScaleMode = AutoScaleMode.Dpi;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), ColumnCount = 1, RowCount = 8 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        foreach (var row in new[] { 0, 1, 2, 3, 5, 6, 7 }) layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Insert(4, new RowStyle(SizeType.Percent, 100));
        var title = new Label { Text = "手机，坐下来控制。", Font = new Font(Font.FontFamily, 23, FontStyle.Bold), AutoSize = true, Dock = DockStyle.Fill, Margin = new Padding(0, 0, 0, 12) };
        _machine.Margin = new Padding(0, 0, 0, 8);
        _status.Margin = new Padding(0, 0, 0, 14);
        _addresses.Margin = new Padding(0, 0, 0, 12);
        var imageArea = new Panel { Dock = DockStyle.Fill, MinimumSize = new Size(280, 280), Margin = new Padding(0, 0, 0, 14) };
        imageArea.Controls.Add(_qr);
        imageArea.Controls.Add(_placeholder);
        var help = new Label { Text = "让 iPhone 和电脑连接同一个家庭网络，\n在手机 Sofa Tap 中扫描这里的二维码。", AutoSize = true, Dock = DockStyle.Fill, Margin = new Padding(0, 0, 0, 8) };
        var privacy = new Label { Text = "二维码可授权控制这台电脑，请勿分享。\n关闭此窗口会退出接收器。", AutoSize = true, Dock = DockStyle.Fill, ForeColor = SystemColors.GrayText, Margin = new Padding(0, 0, 0, 16) };
        var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft, WrapContents = false };
        buttons.Controls.Add(_quit);
        buttons.Controls.Add(_refresh);
        layout.Controls.Add(title, 0, 0);
        layout.Controls.Add(_machine, 0, 1);
        layout.Controls.Add(_status, 0, 2);
        layout.Controls.Add(_addresses, 0, 3);
        layout.Controls.Add(imageArea, 0, 4);
        layout.Controls.Add(help, 0, 5);
        layout.Controls.Add(privacy, 0, 6);
        layout.Controls.Add(buttons, 0, 7);
        Controls.Add(layout);
        _addresses.SelectedIndexChanged += (_, _) => { if (!_updating) RenderQr(); };
        _refresh.Click += async (_, _) => await RefreshAsync();
        _quit.Click += (_, _) => Close();
        _backend.StateReceived += state => OnUi(() => ApplyState(state));
        _backend.Failed += () => OnUi(ShowBackendFailure);
        Shown += (_, _) => StartBackend();
        FormClosing += ClosingAsync;
    }

    private void StartBackend()
    {
        try
        {
            var executable = Path.Combine(AppContext.BaseDirectory, "SofaTapHost.exe");
            if (!File.Exists(executable)) throw new FileNotFoundException();
            _backend.Start(executable, _arguments);
        }
        catch (Exception error) when (error is IOException or InvalidOperationException or System.ComponentModel.Win32Exception)
        { ShowBackendFailure(); }
    }

    private void OnUi(Action action)
    {
        if (IsDisposed || Disposing || !IsHandleCreated) return;
        try { BeginInvoke(action); }
        catch (InvalidOperationException) { }
    }

    private void ApplyState(ReceiverState state)
    {
        if (_stopping) return;
        _machine.Text = state.Name;
        _status.Text = state.DryRun ? "演练模式 · 不会向电脑输入操作" : state.InputStatus switch
        {
            "ready" => state.Connected ? "iPhone 已连接 · 可以控制电脑" : "已就绪 · 等待 iPhone 扫码",
            "accessibility_required" => "需要在电脑上允许接收器控制桌面",
            _ => "请登录并解锁电脑桌面"
        };
        var selected = _addresses.SelectedItem as string;
        _updating = true;
        _pairings = state.Pairings;
        _addresses.Items.Clear();
        _addresses.Items.AddRange(_pairings.Select(pairing => (object)pairing.Host).ToArray());
        var previous = Array.FindIndex(_pairings, pairing => pairing.Host == selected);
        _addresses.SelectedIndex = _pairings.Length == 0 ? -1 : Math.Max(0, previous);
        _updating = false;
        _refresh.Enabled = true;
        RenderQr();
    }

    private void RenderQr()
    {
        var index = _addresses.SelectedIndex;
        if (index < 0 || index >= _pairings.Length) { ClearQr("暂无可用网络地址"); return; }
        var png = _pairings[index].Png;
        if (_renderedPng is not null && png.AsSpan().SequenceEqual(_renderedPng)) return;
        try
        {
            using var stream = new MemoryStream(png, writable: false);
            using var decoded = Image.FromStream(stream);
            var image = new Bitmap(decoded);
            var previous = _qr.Image;
            _qr.Image = image;
            previous?.Dispose();
            _renderedPng = png;
            _placeholder.Hide();
        }
        catch (Exception error) when (error is ArgumentException or OutOfMemoryException)
        { ClearQr("二维码暂时不可用，请刷新"); }
    }

    private void ClearQr(string text)
    {
        var image = _qr.Image;
        _qr.Image = null;
        image?.Dispose();
        _renderedPng = null;
        _placeholder.Text = text;
        _placeholder.Show();
    }

    private void ShowBackendFailure()
    {
        if (_stopping) return;
        _refresh.Enabled = false;
        _pairings = [];
        _status.Text = "接收端连接已中断。请退出并重新打开。";
        ClearQr("请确认完整解压了 Sofa Tap 安装包");
    }

    private async Task RefreshAsync()
    {
        try { await _backend.SendAsync("refresh"); }
        catch (Exception error) when (error is IOException or InvalidOperationException or ObjectDisposedException) { ShowBackendFailure(); }
    }

    private async void ClosingAsync(object? sender, FormClosingEventArgs args)
    {
        if (_allowClose) return;
        args.Cancel = true;
        if (_stopping) return;
        _stopping = true;
        _refresh.Enabled = false;
        _quit.Enabled = false;
        ClearQr("正在退出接收器…");
        try { await _backend.StopAsync(); }
        catch (Exception error) when (error is IOException or InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            _status.Text = "接收进程尚未退出。请重试，或在任务管理器关闭 SofaTapHost。";
            _stopping = false;
            _quit.Enabled = true;
            return;
        }
        _allowClose = true;
        Close();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { _backend.Dispose(); _qr.Image?.Dispose(); }
        base.Dispose(disposing);
    }
}
