import Foundation
import CoreFoundation

/// Optional extension: legacy capability fields retain their original meanings.
struct AndroidTVControls: Equatable, Sendable {
    enum NavigationStatus: String, Sendable { case unsupported, pairingRequired = "pairing_required", pairing, ready, unavailable }
    enum TextStatus: String, Sendable { case imeRequired = "ime_required", noEditor = "no_editor", ready, sensitive }
    let navigationStatus: NavigationStatus
    let textStatus: TextStatus
    let editorEpoch: UUID?

    static func parse(_ value: Any?) throws -> Self? {
        guard let value else { return nil }
        guard let object = value as? [String: Any],
              Set(object.keys).isSubset(of: ["version", "navigationStatus", "textStatus", "editorEpoch"]),
              let version = object["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let navigation = object["navigationStatus"] as? String, let navigationStatus = NavigationStatus(rawValue: navigation),
              let text = object["textStatus"] as? String, let textStatus = TextStatus(rawValue: text) else { throw AndroidTVError.malformedMessage }
        let epoch: UUID?
        if let value = object["editorEpoch"] {
            guard let string = value as? String, let parsed = UUID(uuidString: string), textStatus == .ready else { throw AndroidTVError.malformedMessage }
            epoch = parsed
        } else { epoch = nil }
        guard (textStatus == .ready) == (epoch != nil) else { throw AndroidTVError.malformedMessage }
        return Self(navigationStatus: navigationStatus, textStatus: textStatus, editorEpoch: epoch)
    }
}

enum AndroidTVControlMode: String, CaseIterable { case navigation, pointer }

/// Every committed draft is an insertion, never a replacement of the remote field.
/// A successful ACK removes only its exact local prefix, retaining later dictation.
struct AndroidTVTextDraft: Equatable {
    enum Delivery: Equatable { case ready, sending, sent, rejected, uncertain }
    var text = ""
    private(set) var delivery: Delivery = .ready
    private(set) var pendingText: String?

    mutating func begin() -> String? {
        guard delivery != .sending, delivery != .uncertain, !text.isEmpty,
              text.utf8.count <= 4096, !text.unicodeScalars.contains(where: { $0.value == 0 }) else { return nil }
        pendingText = text; delivery = .sending
        return text
    }
    mutating func accepted() {
        guard let sent = pendingText else { return }
        pendingText = nil
        if text.hasPrefix(sent) {
            text.removeFirst(sent.count)
            delivery = .sent
        } else {
            // The user changed the submitted prefix before its ACK. Preserve it
            // without guessing which characters now represent already sent text.
            delivery = .uncertain
        }
    }
    mutating func rejected() { pendingText = nil; delivery = .rejected }
    mutating func interrupted(wasSent: Bool) {
        guard pendingText != nil else { return }
        pendingText = nil; delivery = wasSent ? .uncertain : .ready
    }
    mutating func markUncertain() { pendingText = nil; delivery = .uncertain }
    mutating func resolve() { guard delivery != .sending else { return }; delivery = .ready }
    mutating func clear() { guard delivery != .sending else { return }; text = ""; delivery = .ready }
}

/// A finger move is discrete navigation only in the explicitly selected remote mode.
/// Limit to one step per update, with hysteresis and no delayed or timer-driven replay.
struct AndroidTVNavigationGesture {
    static let threshold = 28.0
    static let interval = 0.12
    private var originX = 0.0, originY = 0.0, lastTime = -Double.infinity
    private(set) var moved = false
    mutating func reset() { self = Self() }
    mutating func move(x: Double, y: Double, time: Double) -> AndroidTVKey? {
        guard x.isFinite, y.isFinite, time.isFinite else { return nil }
        if hypot(x, y) >= 10 { moved = true }
        let dx = x - originX, dy = y - originY
        guard max(abs(dx), abs(dy)) >= Self.threshold, time - lastTime >= Self.interval else { return nil }
        originX = x; originY = y; lastTime = time
        return abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
    }
}


/// Tracks a single contact. Cancellation, multi-touch and long holds never
/// become an accidental OK when a finger is lifted.
struct AndroidTVNavigationContact {
    private var motion = AndroidTVNavigationGesture()
    private var startX = 0.0, startY = 0.0, startedAt = 0.0
    private(set) var active = false
    mutating func begin(x: Double, y: Double, time: Double) {
        cancel()
        guard x.isFinite, y.isFinite, time.isFinite else { return }
        startX = x; startY = y; startedAt = time; active = true
    }
    mutating func move(x: Double, y: Double, time: Double) -> AndroidTVKey? {
        guard active, time >= startedAt else { return nil }
        return motion.move(x: x - startX, y: y - startY, time: time)
    }
    mutating func end(x: Double, y: Double, time: Double) -> AndroidTVKey? {
        guard active, x.isFinite, y.isFinite else { cancel(); return nil }
        // A fast swipe can have no intermediate sample. Respect the same
        // distance/rate limits for its final position, without replaying steps.
        let finalDirection = move(x: x, y: y, time: time)
        let isTap = time.isFinite && time >= startedAt && time - startedAt <= 0.45 && !motion.moved
        cancel()
        return finalDirection ?? (isTap ? .confirm : nil)
    }
    mutating func cancel() { active = false; motion.reset() }
}
