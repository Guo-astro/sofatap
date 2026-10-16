import Foundation

/// Presentation-only device context. Help and practice never send remote input.
struct DeviceGuideContext: Equatable {
    enum Kind: String {
        case computer, windows, macos, linux, androidTV, webOS

        var target: GestureTarget {
            switch self {
            case .androidTV, .webOS: return .television
            default: return .computer
            }
        }

        static func computer(platform: String?) -> Self {
            switch platform {
            case "windows": return .windows
            case "macos": return .macos
            case "linux": return .linux
            default: return .computer
            }
        }
    }

    enum Availability { case disabled, supported, unsupported, unknown }

    let kind: Kind
    let deviceName: String
    let connected: Bool
    /// nil means capabilities have not been reported, not that everything works.
    let availableActions: Set<GestureAction>?
    var tvNavigation = false
    var tvNavigationReady = false
    var tvTextStatus: String? = nil

    var target: GestureTarget { kind.target }
    var showsTextInputHelp: Bool { target == .computer }
    var televisionActions: [GestureAction] { tvNavigation ? [.confirm, .back, .home] : [.movePointer, .leftClick, .scroll, .confirm, .back, .home] }
    var showsTVTextInputHelp: Bool { kind == .androidTV && tvTextStatus != nil }

    func availability(of action: GestureAction) -> Availability {
        guard action != .none else { return .disabled }
        // Computer-only mappings must never be presented as supported TV input,
        // even if a future caller passes a broader capability set.
        if target == .television && !televisionActions.contains(action) { return .unsupported }
        guard connected, let availableActions else { return .unknown }
        if tvNavigation && televisionActions.contains(action) { return tvNavigationReady ? .supported : .unsupported }
        return availableActions.contains(action) ? .supported : .unsupported
    }

    func configuration(_ stored: GestureConfiguration) -> GestureConfiguration {
        stored.sanitized(for: target)
    }
}
