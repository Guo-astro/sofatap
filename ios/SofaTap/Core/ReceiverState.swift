import Foundation

/// Additive protocol-v1 metadata. Older receivers omit it; unavailable never implies dry-run.
struct ReceiverState: Equatable {
    enum Platform: String { case windows, macos, linux, unknown }
    enum Status: String { case ready, dry_run, accessibility_required, desktop_unavailable, unavailable }

    var platform: Platform = .unknown
    var status: Status = .unavailable
    var inputAvailable: Bool = false
    var dryRun: Bool = false
    var commandModifier: String { platform == .macos ? "win" : "ctrl" }
    var unavailableTitle: String {
        switch status {
        case .dry_run: return "演练接收器 · 不会操作电脑"
        case .accessibility_required: return "Mac 等待辅助功能授权"
        case .desktop_unavailable: return "请登录并解锁电脑"
        default: return "电脑暂时无法接受操作"
        }
    }
    var unavailableMessage: String {
        switch status {
        case .dry_run: return "接收器正在演练模式，鼠标和文字操作已停用。"
        case .accessibility_required: return "请在 Mac 接收器页面打开辅助功能授权，并在系统设置中允许 Sofa Tap。"
        case .desktop_unavailable: return "请登录并解锁电脑，保持桌面打开；连接会自动检查状态。"
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
        return ReceiverState(platform: platform, status: status,
                             inputAvailable: available && status == .ready && !dry, dryRun: dry)
    }
}
