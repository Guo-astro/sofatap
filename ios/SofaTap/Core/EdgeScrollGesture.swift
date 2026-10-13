import Foundation

/// Relative vertical scrolling in the same point units and direction as TouchGestureState.
/// This is not a document scrollbar: there is no remote position, inertia, or queued tail.
struct EdgeScrollGesture {
    static let movementThreshold = 3.0
    static let maximumDelta = 120.0
    static let accessibilityStep = 60.0

    private enum Phase { case idle, primed, scrolling, suppressed }
    private var phase = Phase.idle
    private var originY = 0.0
    private var previousY = 0.0

    var isContactActive: Bool { phase == .primed || phase == .scrolling }
    var isScrolling: Bool { phase == .scrolling }

    mutating func begin(y: Double, count: Int) {
        guard count == 1, y.isFinite, phase == .idle else { suppress(); return }
        originY = y
        previousY = y
        phase = .primed
    }

    /// Positive screen-space finger movement produces a negative wheel delta (document down).
    mutating func move(y: Double, count: Int) -> Double? {
        guard count == 1, y.isFinite else { suppress(); return nil }
        guard phase == .primed || phase == .scrolling else { return nil }
        let delta: Double
        if phase == .primed {
            guard abs(y - originY) >= Self.movementThreshold else { return nil }
            delta = y - originY
            phase = .scrolling
        } else {
            delta = y - previousY
        }
        previousY = y
        // Rebase after a large sample. Dropped excess must not replay in a later packet.
        guard delta.isFinite, delta != 0 else { return nil }
        return max(-Self.maximumDelta, min(Self.maximumDelta, -delta))
    }

    mutating func end(remainingCount: Int) {
        if remainingCount == 0 { cancel() }
        else { suppress() }
    }

    /// Multitouch remains suppressed until every contact is lifted, never resuming on one finger.
    mutating func suppress() { phase = .suppressed; originY = 0; previousY = 0 }

    mutating func cancel() { phase = .idle; originY = 0; previousY = 0 }
}
