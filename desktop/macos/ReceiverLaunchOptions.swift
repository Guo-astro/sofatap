import Foundation
import CoreGraphics

/// The display option is intentionally restricted to non-injecting QA sessions.
/// Keep parsing and geometry independent of AppKit so failures can be tested
/// without creating an application, window, receiver or network listener.
struct ReceiverLaunchOptions: Equatable {
    let testDisplayID: UInt32?

    static func parse(_ arguments: [String]) throws -> Self {
        let selectors = arguments.indices.filter { arguments[$0].hasPrefix("--test-display-id") }
        guard !selectors.isEmpty else { return Self(testDisplayID: nil) }
        guard selectors.count == 1, let index = selectors.first,
              arguments[index] == "--test-display-id", index + 1 < arguments.count else {
            throw ReceiverLaunchError.invalidDisplayArgument
        }
        let value = arguments[index + 1]
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let id = UInt32(value), id != 0 else {
            throw ReceiverLaunchError.invalidDisplayArgument
        }
        guard arguments.contains("--dry-run") else { throw ReceiverLaunchError.requiresDryRun }
        // Do not silently accept misspelled QA options or activate a normal launch.
        var remaining = arguments
        remaining.removeSubrange(index...index + 1)
        guard remaining == ["--dry-run"] else { throw ReceiverLaunchError.invalidDisplayArgument }
        return Self(testDisplayID: id)
    }
}

struct ReceiverDisplaySnapshot {
    let id: UInt32
    let visibleFrame: CGRect
    let isPrimary: Bool
    let isMirrored: Bool
    let isActive: Bool
}

enum ReceiverTestPlacement {
    static func frame(displayID: UInt32, displays: [ReceiverDisplaySnapshot],
                      preferredSize: CGSize, minimumSize: CGSize) throws -> CGRect {
        let matching = displays.filter { $0.id == displayID }
        guard matching.count == 1, let display = matching.first, display.isActive else {
            throw ReceiverLaunchError.displayUnavailable
        }
        guard !display.isPrimary, !display.isMirrored else { throw ReceiverLaunchError.displayNotIsolated }
        let visible = display.visibleFrame
        guard [visible.origin.x, visible.origin.y, visible.width, visible.height,
               preferredSize.width, preferredSize.height, minimumSize.width, minimumSize.height]
            .allSatisfy({ $0.isFinite }),
              minimumSize.width > 0, minimumSize.height > 0,
              preferredSize.width >= minimumSize.width, preferredSize.height >= minimumSize.height,
              visible.size.width > 0, visible.size.height > 0,
              visible.width >= minimumSize.width, visible.height >= minimumSize.height else {
            throw ReceiverLaunchError.displayTooSmall
        }
        let size = CGSize(width: min(preferredSize.width, visible.width),
                          height: min(preferredSize.height, visible.height))
        return CGRect(x: visible.minX + (visible.width - size.width) / 2,
                      y: visible.minY + (visible.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

enum ReceiverLaunchError: Error, CustomStringConvertible {
    case invalidDisplayArgument, requiresDryRun, displayUnavailable, displayNotIsolated, displayTooSmall

    var description: String {
        switch self {
        case .invalidDisplayArgument: return "Use --dry-run --test-display-id followed by one numeric display ID."
        case .requiresDryRun: return "--test-display-id requires --dry-run."
        case .displayUnavailable: return "The requested test display is not available."
        case .displayNotIsolated: return "The test display must be non-primary and not mirrored."
        case .displayTooSmall: return "The test display cannot contain the receiver window."
        }
    }
}
