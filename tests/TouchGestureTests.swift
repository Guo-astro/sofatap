import Foundation

@main
struct TouchGestureTests {
    static func main() {
        typealias State = TouchGestureState
        typealias Action = State.Action
        var passed = 0
        let origin = State.Point(x: 100, y: 100)
        let far = State.Point(x: 180, y: 170)
        func check(_ title: String, _ condition: Bool) {
            precondition(condition, title)
            passed += 1
        }
        func begin(_ state: inout State, _ time: Double = 0) -> [Action] {
            state.begin(at: origin, count: 1, time: time)
        }
        func end(_ state: inout State, _ time: Double) -> [Action] {
            state.end(at: origin, remainingCount: 0, time: time)
        }

        var single = State()
        check("touch starts without clicking", begin(&single).isEmpty)
        check("single release is deferred", end(&single, 0.05).isEmpty)
        check("single does not fire inside double-tap interval", single.advance(to: 0.329).isEmpty)
        check("single fires after double-tap interval", single.advance(to: 0.331) == [.leftClick])
        check("single never repeats", single.advance(to: 2).isEmpty)

        var double = State()
        _ = begin(&double); _ = end(&double, 0.04)
        check("second touch consumes pending single", begin(&double, 0.14).isEmpty)
        check("one finger double tap sends ONLY right click", end(&double, 0.20) == [.rightClick])
        check("double tap has no delayed left click", double.advance(to: 2).isEmpty)

        var separated = State()
        _ = begin(&separated); _ = end(&separated, 0.04)
        check("separate distant tap flushes first left click", separated.begin(at: far, count: 1, time: 0.12) == [.leftClick])
        check("second distinct single is deferred", separated.end(at: far, remainingCount: 0, time: 0.16).isEmpty)
        check("second distinct single fires once", separated.advance(to: 1) == [.leftClick])

        var hold = State()
        _ = begin(&hold)
        check("hold cannot begin before 300ms", hold.advance(to: 0.299).isEmpty && !hold.isDragging)
        check("hold begins at exactly 300ms", hold.advance(to: 0.300) == [.dragging(true)] && hold.isDragging)
        check("hold does not repeat down", hold.advance(to: 0.4).isEmpty)
        check("drag movement reaches receiver", hold.move(to: .init(x: 114, y: 106), count: 1, time: 0.42) == [.move(14, 6)])
        check("release ends drag without click", hold.end(at: .init(x: 114, y: 106), remainingCount: 0, time: 0.5) == [.dragging(false)])
        check("released hold has no delayed click", hold.advance(to: 2).isEmpty && !hold.isDragging)

        var cancelledHold = State()
        _ = begin(&cancelledHold); _ = cancelledHold.advance(to: 0.3)
        check("cancel releases held button", cancelledHold.cancel() == [.dragging(false)])
        check("repeated cancel is idempotent", cancelledHold.cancel().isEmpty)
        check("cancel clears timer", cancelledHold.nextDeadline == nil)

        var cancelledTap = State()
        _ = begin(&cancelledTap); _ = end(&cancelledTap, 0.03)
        check("cancel drops deferred tap", cancelledTap.cancel().isEmpty && cancelledTap.advance(to: 5).isEmpty)
        var earlyCancel = State()
        _ = begin(&earlyCancel)
        check("background before hold cannot arm later", earlyCancel.cancel().isEmpty && earlyCancel.advance(to: 5).isEmpty)

        var slide = State()
        _ = begin(&slide)
        check("slide moves without waiting 300ms", slide.move(to: .init(x: 110, y: 100), count: 1, time: 0.05) == [.move(10, 0)])
        check("moving finger never becomes hold", slide.advance(to: 0.5).isEmpty)
        check("slide lift never clicks", slide.end(at: .init(x: 110, y: 100), remainingCount: 0, time: 0.6).isEmpty)
        var delayedTimer = State()
        _ = begin(&delayedTimer)
        check("delayed timer cannot turn existing movement into drag", delayedTimer.move(to: far, count: 1, time: 0.4) == [.move(80, 70)])

        var jitter = State()
        _ = begin(&jitter)
        check("stationary jitter does not move cursor", jitter.move(to: .init(x: 102, y: 101), count: 1, time: 0.15).isEmpty)
        check("stationary jitter still permits 300ms hold", jitter.advance(to: 0.3) == [.dragging(true)])
        _ = jitter.cancel()

        var scroll = State()
        _ = begin(&scroll)
        check("second finger cancels hold", scroll.begin(at: origin, count: 2, time: 0.1).isEmpty && scroll.nextDeadline == nil)
        check("two finger move scrolls without moving cursor", scroll.move(to: .init(x: 120, y: 140), count: 2, time: 0.2) == [.scroll(-40)])
        check("scroll finger lift is silent", scroll.end(at: origin, remainingCount: 1, time: 0.25).isEmpty)
        check("remaining scroll finger cannot move pointer", scroll.move(to: far, count: 1, time: 0.3).isEmpty)
        check("scroll release never clicks", end(&scroll, 0.4).isEmpty && scroll.advance(to: 2).isEmpty)

        var scrollAfterDrag = State()
        _ = begin(&scrollAfterDrag); _ = scrollAfterDrag.advance(to: 0.3)
        check("adding second finger releases active drag", scrollAfterDrag.begin(at: origin, count: 2, time: 0.4) == [.dragging(false)])
        check("two fingers cannot leave sticky hold", !scrollAfterDrag.isDragging)
        _ = scrollAfterDrag.cancel()

        var secondHold = State()
        _ = begin(&secondHold); _ = end(&secondHold, 0.03); _ = begin(&secondHold, 0.12)
        check("holding second touch starts drag without phantom left click", secondHold.advance(to: 0.43) == [.dragging(true)])
        check("holding second touch does not right click", end(&secondHold, 0.5) == [.dragging(false)])
        check("holding second touch leaves no delayed action", secondHold.advance(to: 3).isEmpty)

        var thirdFinger = State()
        _ = thirdFinger.begin(at: origin, count: 3, time: 0)
        check("three fingers suppressed", thirdFinger.move(to: far, count: 3, time: 0.2).isEmpty)
        check("three finger lift never clicks", end(&thirdFinger, 0.3).isEmpty)
        print("PASS \(passed) touch gesture checks (deterministic, no desktop input)")
    }
}
