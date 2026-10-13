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
        check("two fingers down pull content down (wheel up) without moving cursor", scroll.move(to: .init(x: 120, y: 140), count: 2, time: 0.2) == [.scroll(40)])
        check("two fingers up push content up (wheel down)", scroll.move(to: .init(x: 120, y: 110), count: 2, time: 0.21) == [.scroll(-30)])
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

        var tvTap = State(profile: .tvPointer)
        check("TV touch starts silently", begin(&tvTap).isEmpty)
        check("TV single tap confirms immediately on lift", end(&tvTap, 0.05) == [.leftClick])
        check("TV tap leaves no pending timer", tvTap.nextDeadline == nil)
        _ = begin(&tvTap, 0.14)
        check("TV second quick tap confirms again instead of right clicking", end(&tvTap, 0.20) == [.leftClick])
        check("TV taps never repeat later", tvTap.advance(to: 2).isEmpty)

        var tvHold = State(profile: .tvPointer)
        _ = begin(&tvHold)
        check("TV stationary hold before deadline stays silent", tvHold.advance(to: 0.299).isEmpty)
        check("TV stationary hold never presses a button", tvHold.advance(to: 0.300).isEmpty && !tvHold.isDragging)
        check("TV completed hold clears its deadline", tvHold.nextDeadline == nil)
        check("TV held finger does not click on lift", end(&tvHold, 0.4).isEmpty && tvHold.advance(to: 2).isEmpty)
        _ = begin(&tvHold, 3)
        check("TV tap after a completed hold works normally", end(&tvHold, 3.05) == [.leftClick])

        var tvDelayedHold = State(profile: .tvPointer)
        _ = begin(&tvDelayedHold)
        check("TV delayed timer still suppresses a 300ms lift", end(&tvDelayedHold, 0.300).isEmpty && !tvDelayedHold.isDragging)
        var tvHoldMove = State(profile: .tvPointer)
        _ = begin(&tvHoldMove); _ = tvHoldMove.advance(to: 0.300)
        check("TV movement after hold is normal pointer motion", tvHoldMove.move(to: far, count: 1, time: 0.4) == [.move(80, 70)] && !tvHoldMove.isDragging)
        check("TV moved hold releases no button and clicks nothing", tvHoldMove.end(at: far, remainingCount: 0, time: 0.5).isEmpty)

        var tvScroll = State(profile: .tvPointer)
        _ = begin(&tvScroll)
        check("TV second finger cancels pending hold", tvScroll.begin(at: origin, count: 2, time: 0.1).isEmpty && tvScroll.nextDeadline == nil)
        check("TV two fingers down pull content down (wheel up)", tvScroll.move(to: .init(x: 120, y: 140), count: 2, time: 0.2) == [.scroll(40)])
        check("TV two fingers up push content up (wheel down)", tvScroll.move(to: .init(x: 120, y: 110), count: 2, time: 0.21) == [.scroll(-30)])
        _ = tvScroll.end(at: origin, remainingCount: 1, time: 0.25)
        check("TV remaining scroll finger cannot move or click", tvScroll.move(to: far, count: 1, time: 0.3).isEmpty && end(&tvScroll, 0.4).isEmpty)

        var switchPending = State()
        _ = begin(&switchPending); _ = end(&switchPending, 0.03)
        check("switch to TV cancels the desktop delayed click", switchPending.changeProfile(to: .tvPointer).isEmpty && switchPending.nextDeadline == nil && switchPending.advance(to: 2).isEmpty)
        check("switch ignores the old contact lift", end(&switchPending, 2.1).isEmpty)
        _ = begin(&switchPending, 3)
        check("first new TV contact confirms immediately", end(&switchPending, 3.05) == [.leftClick])

        var switchDrag = State()
        _ = begin(&switchDrag); _ = switchDrag.advance(to: 0.300)
        check("profile switch returns exactly one old-target drag release", switchDrag.changeProfile(to: .tvPointer) == [.dragging(false)] && !switchDrag.isDragging)
        check("same TV profile preserves the cancellation boundary", switchDrag.changeProfile(to: .tvPointer).isEmpty && switchDrag.advance(to: 2).isEmpty)
        _ = begin(&switchDrag, 3)
        check("TV to desktop cancels a live TV contact without a key event", switchDrag.changeProfile(to: .desktop).isEmpty && end(&switchDrag, 3.05).isEmpty)
        _ = begin(&switchDrag, 4)
        check("desktop semantics return after switching back", switchDrag.advance(to: 4.3) == [.dragging(true)])
        _ = switchDrag.cancel()
        print("PASS \(passed) touch gesture checks (deterministic, no desktop input)")
    }
}
