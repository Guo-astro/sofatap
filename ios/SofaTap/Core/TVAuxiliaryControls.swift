import Foundation
import CoreGraphics

/// Fixed common control anchors belong to RemoteView. Only the TV tools adapt.
struct TVAuxiliaryLayout {
    let vertical: Bool
    var width: Double { vertical ? 44 : 88 }
    var height: Double { vertical ? 100 : 56 }
    static let trailing = 16.0
    static let bottom = 20.0
    init(cardWidth: Double) { vertical = cardWidth < 288 }
    func frame(cardWidth: Double, cardHeight: Double) -> CGRect {
        let x = CGFloat(cardWidth - Self.trailing - width)
        let y = CGFloat(cardHeight - Self.bottom - height)
        return CGRect(x: x, y: y, width: CGFloat(width), height: CGFloat(height))
    }
    func buttonFrame(_ index: Int) -> CGRect {
        let offset = CGFloat(index) * 44
        return CGRect(x: vertical ? 0 : offset, y: vertical ? offset : 0, width: 44, height: 44)
    }
}

/// A toolbar contact ends in one local page change or one button activation.
/// A swipe never becomes a click, and no motion is forwarded to the TV surface.
struct TVAuxiliaryGesture {
    enum Outcome: Equatable { case activate(Int), page(Int) }
    private var startX = 0.0, startY = 0.0, beganAt = 0.0
    private var startButton: Int?
    private(set) var active = false
    private(set) var moved = false
    mutating func begin(x: Double, y: Double, time: Double, button: Int?) {
        cancel()
        guard x.isFinite, y.isFinite, time.isFinite else { return }
        active = true; startX = x; startY = y; beganAt = time; startButton = button
    }
    mutating func move(x: Double, y: Double) {
        guard active, x.isFinite, y.isFinite else { return }
        if hypot(x - startX, y - startY) >= 8 { moved = true }
    }
    mutating func end(x: Double, y: Double, time: Double, button: Int?) -> Outcome? {
        guard active, x.isFinite, y.isFinite, time.isFinite, time >= beganAt else { cancel(); return nil }
        move(x: x, y: y)
        let dx = x - startX, dy = y - startY
        let outcome: Outcome?
        if abs(dx) >= 24 && abs(dx) > abs(dy) * 1.2 {
            outcome = .page(dx < 0 ? 1 : -1)
        } else if !moved, time - beganAt <= 0.65, let startButton, startButton == button {
            outcome = .activate(startButton)
        } else { outcome = nil }
        cancel(); return outcome
    }
    mutating func cancel() { active = false; moved = false; startButton = nil }
    static func page(_ page: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(0, page + delta), count - 1)
    }
}
