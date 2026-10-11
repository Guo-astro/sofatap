namespace SofaTap;

// OS-specific event injection stays behind IInputInjector. Transport and pairing are shared.
public static class ReceiverPlatform
{
    public static string Id => OperatingSystem.IsWindows() ? "windows" : OperatingSystem.IsMacOS() ? "macos" : OperatingSystem.IsLinux() ? "linux" : "unknown";
    public static string DisplayName => Id switch { "windows" => "Windows", "macos" => "Mac", "linux" => "Linux", _ => "Computer" };

    public static string StatusCode(IInputInjector input, bool dryRun) => dryRun ? "dry_run"
        : input is MacInput mac ? mac.StatusCode
        : input.Available ? "ready" : "desktop_unavailable";

    public static string StatusMessage(string code) => code switch
    {
        "dry_run" => "演练模式 · 不会操作电脑",
        "ready" => $"桌面可用 · 可以向 {DisplayName} 提交操作",
        "accessibility_required" => "请在 Mac 的系统设置中允许 Sofa Tap 使用辅助功能",
        _ => $"请登录并解锁 {DisplayName} 桌面"
    };
}
