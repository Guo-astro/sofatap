import Foundation

/// Pure touch semantics. UIKit supplies monotonic timestamps and schedules `nextDeadline`.
/// No mouse input is sent by this type, which also makes cancellation/timing testable.
struct TouchGestureState {
    struct Point: Equatable {
        var x: Double
        var y: Double
        func distance(to other: Self) -> Double { hypot(x - other.x, y - other.y) }
    }
    enum Action: Equatable {
        case move(Double, Double), leftClick, rightClick, dragging(Bool), scroll(Double)
    }
    private enum Mode { case idle, one, two, suppressed }
    static let holdDuration = 0.300
    static let doubleTapInterval = 0.280
    private let movementTolerance = 7.0
    private let doubleTapDistance = 32.0
    private var mode = Mode.idle
    private var origin = Point(x: 0, y: 0)
    private var previous = Point(x: 0, y: 0)
    private var holdDeadline: Double?
    private var moved = false
    private var secondTap = false
    private var pendingTap: (point: Point, deadline: Double)?
    private(set) var isDragging = false

    var nextDeadline: Double? {
        [holdDeadline, pendingTap?.deadline].compactMap { $0 }.min()
    }

    mutating func begin(at point: Point, count: Int, time: Double) -> [Action] {
        guard count > 0 else { return [] }
        if count != 1 || mode != .idle {
            return switchContactCount(count, point: point)
        }
        var actions = advance(to: time)
        secondTap = false
        if let pendingTap {
            if time < pendingTap.deadline && pendingTap.point.distance(to: point) <= doubleTapDistance {
                secondTap = true
            } else {
                actions.append(.leftClick)
            }
        }
        pendingTap = nil
        mode = .one
        origin = point
        previous = point
        moved = false
        holdDeadline = time + Self.holdDuration
        return actions
    }

    mutating func move(to point: Point, count: Int, time: Double) -> [Action] {
        // Apply movement first: a delayed main-run-loop timer must not begin a drag
        // after the finger has already crossed the stationary tolerance.
        guard count > 0 else { return [] }
        if count == 2 && mode != .two { return switchContactCount(count, point: point) }
        if count > 2 || (count == 1 && mode == .two) {
            return switchContactCount(count, point: point)
        }
        guard mode == .one || mode == .two else { return [] }
        let dx = point.x - previous.x, dy = point.y - previous.y
        previous = point
        if mode == .two { return dy == 0 ? [] : [.scroll(-dy)] }
        if origin.distance(to: point) > movementTolerance {
            moved = true
            holdDeadline = nil
        }
        var actions = advance(to: time)
        // Ignore stationary jitter until movement is intentional or drag has started.
        if isDragging || moved {
            if dx != 0 || dy != 0 { actions.append(.move(dx, dy)) }
        }
        return actions
    }

    mutating func end(at point: Point, remainingCount: Int, time: Double) -> [Action] {
        if remainingCount > 0 {
            // Never turn the remaining finger of a scroll into a tap or a drag.
            let actions: [Action] = isDragging ? [.dragging(false)] : []
            resetContact()
            mode = .suppressed
            pendingTap = nil
            return actions
        }
        var actions: [Action] = []
        if mode == .one {
            if origin.distance(to: point) > movementTolerance { moved = true; holdDeadline = nil }
            actions += advance(to: time)
            if isDragging {
                actions.append(.dragging(false))
            } else if !moved {
                if secondTap { actions.append(.rightClick) }
                else { pendingTap = (point, time + Self.doubleTapInterval) }
            }
        }
        resetContact()
        return actions
    }

    mutating func advance(to time: Double) -> [Action] {
        var actions: [Action] = []
        if let pendingTap, time >= pendingTap.deadline {
            self.pendingTap = nil
            actions.append(.leftClick)
        }
        if let holdDeadline, time >= holdDeadline, mode == .one, !moved, !isDragging {
            self.holdDeadline = nil
            pendingTap = nil
            secondTap = false
            isDragging = true
            actions.append(.dragging(true))
        }
        return actions
    }

    /// Interruption, disabled input and removal all drop deferred clicks and release.
    mutating func cancel() -> [Action] {
        let actions: [Action] = isDragging ? [.dragging(false)] : []
        pendingTap = nil
        resetContact()
        return actions
    }

    private mutating func switchContactCount(_ count: Int, point: Point) -> [Action] {
        let actions: [Action] = isDragging ? [.dragging(false)] : []
        resetContact()
        pendingTap = nil
        mode = count == 2 ? .two : .suppressed
        previous = point
        return actions
    }

    private mutating func resetContact() {
        mode = .idle
        holdDeadline = nil
        isDragging = false
        moved = false
        secondTap = false
    }
}
