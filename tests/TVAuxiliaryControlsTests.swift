import Foundation
import CoreGraphics

@main struct TVAuxiliaryControlsTests {
    static func main() {
        var count = 0
        func check(_ message: String, _ condition: @autoclosure () -> Bool) {
            guard condition() else { fatalError("FAIL: " + message) }; count += 1
        }
        var gesture = TVAuxiliaryGesture()
        gesture.begin(x: 20, y: 20, time: 1, button: 0)
        check("stationary contact activates the first button", gesture.end(x: 21, y: 21, time: 1.1, button: 0) == .activate(0))
        check("ended contact cannot activate twice", gesture.end(x: 21, y: 21, time: 1.2, button: 0) == nil)
        gesture.begin(x: 65, y: 20, time: 2, button: 1)
        check("left swipe changes local page instead of activating Home", gesture.end(x: 20, y: 20, time: 2.2, button: 0) == .page(1))
        gesture.begin(x: 20, y: 20, time: 3, button: 0)
        check("right swipe changes local page instead of activating direction keys", gesture.end(x: 65, y: 20, time: 3.2, button: 1) == .page(-1))
        gesture.begin(x: 20, y: 20, time: 4, button: 0)
        check("vertical swipe is swallowed without activating anything", gesture.end(x: 21, y: 60, time: 4.2, button: nil) == nil)
        gesture.begin(x: 20, y: 20, time: 5, button: 0)
        gesture.move(x: 32, y: 20)
        check("returning after movement cannot become a click", gesture.end(x: 20, y: 20, time: 5.2, button: 0) == nil)
        gesture.begin(x: 20, y: 20, time: 6, button: 0); gesture.cancel()
        check("cancelled multi-touch cannot activate on release", gesture.end(x: 20, y: 20, time: 6.2, button: 0) == nil)
        gesture.begin(x: 20, y: 20, time: 7, button: 0)
        check("long hold does not activate a toolbar command", gesture.end(x: 20, y: 20, time: 8, button: 0) == nil)
        gesture.begin(x: 20, y: 20, time: 9, button: 0)
        check("nonfinite contact never activates", gesture.end(x: .nan, y: 20, time: 9.1, button: 0) == nil)
        gesture.begin(x: 20, y: 50, time: 10, button: nil)
        check("page indicators do not act as a remote command", gesture.end(x: 20, y: 50, time: 10.1, button: nil) == nil)
        check("first page cannot underflow", TVAuxiliaryGesture.page(0, delta: -1, count: 2) == 0)
        check("last page cannot overflow", TVAuxiliaryGesture.page(1, delta: 1, count: 2) == 1)
        check("webOS has one page only", TVAuxiliaryGesture.page(0, delta: 1, count: 1) == 0)
        check("reduced page count safely resets page", TVAuxiliaryGesture.page(1, delta: 0, count: 1) == 0)
        for (width, height) in [(296.0, 170.0), (320, 250), (351, 240), (378, 700), (406, 700), (744, 360), (1000, 640), (260, 350)] {
            let layout = TVAuxiliaryLayout(cardWidth: width), tools = TVAuxiliaryLayout(cardWidth: width).frame(cardWidth: width, cardHeight: height)
            let microphone = CGRect(x: width / 2 - 38, y: height - 90, width: 76, height: 76) // includes its visible ring
            let keyboard = CGRect(x: 20, y: height - 78, width: 48, height: 52)
            check("toolbar never covers microphone at \(width)x\(height)", !tools.intersects(microphone))
            check("toolbar never covers keyboard at \(width)x\(height)", !tools.intersects(keyboard))
            check("toolbar stays within dot card at \(width)x\(height)", CGRect(x: 0, y: 0, width: width, height: height).contains(tools))
            check("toolbar stays below header at \(width)x\(height)", tools.minY >= 74)
            for index in 0...1 {
                let hit = layout.buttonFrame(index)
                check("two independent 44pt touch targets at \(width)", hit.width == 44 && hit.height == 44)
            }
        }
        for width in [296.0, 378, 800] {
            for height in [170.0, 180, 200, 210, 220, 240] {
                let layout = TVAuxiliaryLayout(cardWidth: width)
                if let rail = layout.scrollFrame(cardWidth: width, cardHeight: height) {
                    check("short rail respects its native minimum", rail.height >= 44)
                    check("short rail stays inside card", CGRect(x: 0, y: 0, width: width, height: height).contains(rail))
                    check("short rail stays below header", rail.minY >= 80)
                    check("short rail never overlaps TV tools", !rail.intersects(layout.frame(cardWidth: width, cardHeight: height)))
                } else {
                    check("too-short rail is omitted rather than forcing overflow", height < 212)
                }
            }
        }
        let original = TVAuxiliaryActionToken(identity: "tvA", page: 0, actionIdentifier: "back", generation: 1)
        check("same action reference matches current state", original == TVAuxiliaryActionToken(identity: "tvA", page: 0, actionIdentifier: "back", generation: 1))
        check("cached action cannot target a new page", original != TVAuxiliaryActionToken(identity: "tvA", page: 1, actionIdentifier: "directions", generation: 2))
        check("cached action cannot target a different TV", original != TVAuxiliaryActionToken(identity: "tvB", page: 0, actionIdentifier: "back", generation: 2))
        check("cached action stays invalid after returning to original page", original != TVAuxiliaryActionToken(identity: "tvA", page: 0, actionIdentifier: "back", generation: 3))
        print("\(count) TV auxiliary pager gesture/layout checks passed; no device input.")
    }
}
