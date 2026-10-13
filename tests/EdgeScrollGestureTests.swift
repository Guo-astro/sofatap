import Foundation

@main
struct EdgeScrollGestureTests {
    static func main() {
        var passed = 0
        func check(_ title: String, _ value: Bool) { precondition(value, title); passed += 1 }

        var tap = EdgeScrollGesture()
        tap.begin(y: 100, count: 1)
        check("finger down activates indicator", tap.isContactActive && !tap.isScrolling)
        check("small jitter is ignored", tap.move(y: 102, count: 1) == nil)
        tap.end(remainingCount: 0)
        check("tap ends without a click or scroll", !tap.isContactActive)
        check("an end event cannot leave scroll tail", tap.move(y: 110, count: 1) == nil)

        var relative = EdgeScrollGesture()
        relative.begin(y: 100, count: 1)
        check("down finger matches desktop document-down convention", relative.move(y: 112, count: 1) == -12)
        check("subsequent movement is relative", relative.move(y: 115, count: 1) == -3)
        check("reversal immediately scrolls the other way", relative.move(y: 110, count: 1) == 5)
        check("stationary contact does not repeat scroll", relative.move(y: 110, count: 1) == nil)
        relative.end(remainingCount: 0)
        check("lift removes active indicator", !relative.isContactActive && !relative.isScrolling)

        var jitter = EdgeScrollGesture()
        jitter.begin(y: 100, count: 1)
        check("pre-threshold movement stays quiet", jitter.move(y: 101.5, count: 1) == nil)
        check("threshold includes movement since touch down", jitter.move(y: 103, count: 1) == -3)

        var bounded = EdgeScrollGesture()
        bounded.begin(y: 0, count: 1)
        check("a stale large sample is bounded", bounded.move(y: 1000, count: 1) == -120)
        check("discarded distance never replays", bounded.move(y: 1001, count: 1) == -1)
        check("large reverse movement is bounded", bounded.move(y: -1000, count: 1) == 120)

        var multi = EdgeScrollGesture()
        multi.begin(y: 100, count: 1)
        _ = multi.move(y: 110, count: 1)
        multi.begin(y: 110, count: 2)
        check("second finger cancels active indicator", !multi.isContactActive)
        check("multitouch does not scroll", multi.move(y: 120, count: 2) == nil)
        multi.end(remainingCount: 1)
        check("remaining finger cannot restart scroll", multi.move(y: 150, count: 1) == nil)
        multi.end(remainingCount: 0)
        multi.begin(y: 200, count: 1)
        check("new gesture works after all fingers lift", multi.move(y: 210, count: 1) == -10)

        var initialMulti = EdgeScrollGesture()
        initialMulti.begin(y: 0, count: 2)
        check("simultaneous fingers start suppressed", initialMulti.move(y: 20, count: 2) == nil)
        initialMulti.end(remainingCount: 1)
        check("initial multitouch does not become a single gesture", initialMulti.move(y: 40, count: 1) == nil)

        var cancelled = EdgeScrollGesture()
        cancelled.begin(y: 100, count: 1)
        _ = cancelled.move(y: 110, count: 1)
        cancelled.cancel()
        check("cancel clears indicator immediately", !cancelled.isContactActive)
        check("old movement after disabled/target change is ignored", cancelled.move(y: 130, count: 1) == nil)
        cancelled.begin(y: 500, count: 1)
        check("fresh target starts from fresh origin", cancelled.move(y: 510, count: 1) == -10)

        for invalid in [Double.nan, .infinity, -.infinity] {
            var bad = EdgeScrollGesture()
            bad.begin(y: 100, count: 1)
            check("invalid sample is dropped", bad.move(y: invalid, count: 1) == nil)
            check("invalid sample suppresses contact until lift", bad.move(y: 110, count: 1) == nil)
            bad.end(remainingCount: 0)
            bad.begin(y: 200, count: 1)
            check("valid new gesture recovers", bad.move(y: 210, count: 1) == -10)
        }
        check("accessibility steps fit packet limit", EdgeScrollGesture.accessibilityStep <= EdgeScrollGesture.maximumDelta)
        print("Edge scroll gesture checks passed: \(passed)")
    }
}
