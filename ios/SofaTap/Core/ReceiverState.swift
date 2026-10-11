import Foundation
import CoreFoundation

enum RemoteTextFocus: String { case unknown, other, editable, protected }

/// Additive protocol-v1 metadata. Older receivers omit it; unavailable never implies dry-run.
struct ReceiverState: Equatable {
    enum Platform: String { case windows, macos, linux, unknown }
    enum Status: String {
        case ready, dry_run, accessibility_required, desktop_unavailable, unavailable
        case permission_required, permission_pending, permission_denied, unsupported_session, dependency_missing, input_unavailable
    }

    var platform: Platform = .unknown
    var status: Status = .unavailable
    var inputAvailable: Bool = false
    var dryRun: Bool = false
    var textFocus: RemoteTextFocus = .unknown
    var focusRevision: Int = 0
    var reportsTextFocus: Bool = false
    var commandModifier: String { platform == .macos ? "win" : "ctrl" }
    var unavailableTitle: String {
        switch status {
        case .dry_run: return "演练接收器 · 不会操作电脑"
        case .accessibility_required: return "Mac 等待辅助功能授权"
        case .desktop_unavailable: return "请登录并解锁电脑"
        case .permission_required, .permission_denied: return "Linux 等待桌面控制授权"
        case .permission_pending: return "请确认 Linux 系统授权"
        case .unsupported_session: return "当前 Linux 桌面尚不支持控制"
        case .dependency_missing: return "Linux 接收器缺少系统组件"
        case .input_unavailable: return "电脑输入组件已停止"
        default: return "电脑暂时无法接受操作"
        }
    }
    var unavailableMessage: String {
        switch status {
        case .dry_run: return "接收器正在演练模式，鼠标和文字操作已停用。"
        case .accessibility_required: return "请在 Mac 接收器页面打开辅助功能授权，并在系统设置中允许 Sofatap。"
        case .desktop_unavailable: return "请登录并解锁电脑，保持桌面打开；连接会自动检查状态。"
        case .permission_required, .permission_denied: return "请在 Linux 接收器点允许控制桌面，再完成系统授权。"
        case .permission_pending: return "请在 Linux 原生系统窗口中确认；完成后会自动检查状态。"
        case .unsupported_session: return "请查看 Linux 接收器说明，确认桌面提供受支持的 X11 或 Wayland 远程控制接口。"
        case .dependency_missing: return "请按 Linux 接收器说明安装所需组件，再重新打开接收器。"
        case .input_unavailable: return "请查看电脑接收器，重新授权或重启后再连接；不要自动重发文字。"
        default: return "接收器已连接，但输入尚不可用。请查看电脑接收器页面。"
        }
    }

    static func hello(_ message: [String: Any]) -> ReceiverState? {
        guard let available = message["inputAvailable"] as? Bool else { return nil }
        let platform = (message["platform"] as? String).flatMap(Platform.init(rawValue:)) ?? .unknown
        return make(platform: platform, available: available, message: message)
    }

    func updating(_ message: [String: Any]) -> ReceiverState? {
        // Legacy ACKs have no availability metadata and leave state unchanged.
        guard let available = message["inputAvailable"] as? Bool,
              message["dryRun"] is Bool, message["inputStatus"] is String else { return nil }
        return Self.make(platform: platform, available: available, message: message)
    }

    private static func make(platform: Platform, available: Bool, message: [String: Any]) -> ReceiverState {
        let dry = message["dryRun"] as? Bool ?? false
        let code = (message["inputStatus"] as? String).flatMap(Status.init(rawValue:))
        let status: Status = dry ? .dry_run : code ?? (message["inputStatus"] == nil && available ? .ready : .unavailable)
        let canInput = available && status == .ready && !dry
        var state = ReceiverState(platform: platform, status: status, inputAvailable: canInput, dryRun: dry)
        if let focus = message["textFocus"] as? [String: Any],
           let raw = focus["state"] as? String, let kind = RemoteTextFocus(rawValue: raw),
           let revision = focus["revision"] as? NSNumber,
           CFGetTypeID(revision) != CFBooleanGetTypeID(),
           revision.doubleValue.isFinite, revision.doubleValue >= 0,
           revision.doubleValue <= Double(Int32.max), revision.doubleValue.rounded() == revision.doubleValue {
            state.reportsTextFocus = true
            if canInput { state.textFocus = kind; state.focusRevision = revision.intValue }
        }
        return state
    }
}
