import Foundation
import CoreGraphics

@main
enum ReceiverLaunchOptionsTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func rejects(_ message: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(message) }
            catch { checks += 1 }
        }
        check(try ReceiverLaunchOptions.parse([]).testDisplayID == nil, "normal launch preserved")
        check(try ReceiverLaunchOptions.parse(["--dry-run"]).testDisplayID == nil, "normal dry-run preserved")
        check(try ReceiverLaunchOptions.parse(["-psn_0_1234"]).testDisplayID == nil, "ordinary Launch Services arguments preserved")
        check(try ReceiverLaunchOptions.parse(["--dry-run", "--test-display-id", "20"]).testDisplayID == 20, "valid QA launch")
        check(try ReceiverLaunchOptions.parse(["--test-display-id", "20", "--dry-run"]).testDisplayID == 20, "QA argument order independent")
        for value in ["", "0", "-1", "+20", "20.0", "２０", "4294967296", " 20", "20\n"] {
            rejects("reject invalid display ID") { _ = try ReceiverLaunchOptions.parse(["--dry-run", "--test-display-id", value]) }
        }
        for args in [
            ["--test-display-id", "20"], ["--dry-run", "--test-display-id"],
            ["--dry-run", "--test-display-id=20"], ["--dry-run", "--test-display-id-extra", "20"],
            ["--dry-run", "--test-display-id", "20", "--test-display-id", "21"],
            ["--dry-run", "--test-display-id", "20", "--unknown"],
            ["--dry-run", "--dry-run", "--test-display-id", "20"],
        ] {
            rejects("invalid QA invocation fails instead of normal launch") { _ = try ReceiverLaunchOptions.parse(args) }
        }
        let preferred = CGSize(width: 470, height: 728), minimum = CGSize(width: 380, height: 468)
        func screen(_ id: UInt32 = 20, frame: CGRect = CGRect(x: 2560, y: -175, width: 1920, height: 1080),
                    primary: Bool = false, mirrored: Bool = false, active: Bool = true) -> ReceiverDisplaySnapshot {
            ReceiverDisplaySnapshot(id: id, visibleFrame: frame, isPrimary: primary, isMirrored: mirrored, isActive: active)
        }
        func place(_ displays: [ReceiverDisplaySnapshot]) throws -> CGRect {
            try ReceiverTestPlacement.frame(displayID: 20, displays: displays, preferredSize: preferred, minimumSize: minimum)
        }
        let target = screen()
        let frame = try place([screen(1, primary: true), target])
        check(frame == CGRect(x: 3285, y: 1, width: 470, height: 728), "center in AppKit visible coordinates")
        check(target.visibleFrame.contains(frame), "frame entirely inside test screen")
        let left = screen(frame: CGRect(x: -1200, y: 0, width: 1200, height: 800))
        check(left.visibleFrame.contains(try place([left])), "negative display coordinates are valid")
        let narrow = screen(frame: CGRect(x: 20, y: 40, width: 400, height: 500))
        check(try place([narrow]) == narrow.visibleFrame, "clamp large preferred window to available visible frame")
        for display in [screen(primary: true), screen(mirrored: true), screen(active: false),
                        screen(frame: CGRect(x: 0, y: 0, width: 379, height: 800)),
                        screen(frame: CGRect(x: 0, y: 0, width: 1000, height: 467)),
                        screen(frame: CGRect(x: 0, y: 0, width: -1000, height: 800)),
                        screen(frame: CGRect(x: CGFloat.nan, y: 0, width: 1000, height: 800))] {
            rejects("unusable target must never fall back to primary") { _ = try place([display]) }
        }
        rejects("absent screen") { _ = try place([]) }
        rejects("different ID") { _ = try place([screen(21)]) }
        rejects("duplicate screen ID") { _ = try place([screen(), screen()]) }
        print("PASS: \(checks) QA launch and placement checks (no application, window, backend, network or input)")
    }
}
