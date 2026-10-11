namespace SofaTap;

// OS-specific event injection stays behind IInputInjector. Transport and pairing are shared.
public static class ReceiverPlatform
{
    public static string Id => OperatingSystem.IsWindows() ? "windows" : OperatingSystem.IsMacOS() ? "macos" : OperatingSystem.IsLinux() ? "linux" : "unknown";
    public static string DisplayName => Id switch { "windows" => "Windows", "macos" => "Mac", "linux" => "Linux", _ => "Computer" };

    public static string StatusCode(IInputInjector input, bool dryRun) => dryRun ? "dry_run"
        : input is MacInput mac ? mac.StatusCode
        : input is LinuxInput linux ? linux.StatusCode
        : input.Available ? "ready" : "desktop_unavailable";

    public static string StatusMessage(string code) => code switch
    {
        "dry_run" => "演练模式 · 不会操作电脑",
        "ready" => $"桌面可用 · 可以向 {DisplayName} 提交操作",
        "accessibility_required" => "请在 Mac 的系统设置中允许 Sofa Tap 使用辅助功能",
        "permission_required" or "permission_denied" => "请在 Linux 接收器中允许控制桌面",
        "permission_pending" => "请在 Linux 系统窗口中确认桌面控制授权",
        "unsupported_session" => "当前 Linux 桌面不提供支持的远程控制接口",
        "dependency_missing" => "请安装 Linux 接收器所需的系统组件",
        "input_unavailable" => "输入组件已停止，请重新打开接收器",
        _ => $"请登录并解锁 {DisplayName} 桌面"
    };
}
