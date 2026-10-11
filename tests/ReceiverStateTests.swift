import Foundation

@main
struct ReceiverStateTests {
    static func main() {
        var passed = 0
        func check(_ name: String, _ value: Bool) {
            precondition(value, name); passed += 1
        }
        let old = ReceiverState.hello(["inputAvailable": true])!
        check("legacy Windows shortcut remains Control", old.inputAvailable && old.commandModifier == "ctrl")
        let locked = ReceiverState.hello(["inputAvailable": false])!
        check("legacy unavailable does not claim dry-run", !locked.dryRun && locked.status == .unavailable)
        let mac = ReceiverState.hello(["platform": "macos", "inputAvailable": false, "dryRun": false, "inputStatus": "accessibility_required"])!
        check("Mac authorization state", mac.status == .accessibility_required && !mac.inputAvailable && mac.commandModifier == "win")
        let ready = mac.updating(["inputAvailable": true, "dryRun": false, "inputStatus": "ready"])!
        check("permission can become available without reconnect", ready.platform == .macos && ready.inputAvailable)
        let revoked = ready.updating(["inputAvailable": false, "dryRun": false, "inputStatus": "desktop_unavailable"])!
        check("lock disables input", !revoked.inputAvailable && revoked.status == .desktop_unavailable)
        check("legacy ACK ignored", ready.updating(["ok": true]) == nil)
        check("incomplete heartbeat metadata ignored", ready.updating(["inputAvailable": true]) == nil)
        let inconsistent = ReceiverState.hello(["inputAvailable": true, "dryRun": true, "inputStatus": "ready"])!
        check("dry-run overrides claimed availability", !inconsistent.inputAvailable && inconsistent.status == .dry_run)
        let unknown = ReceiverState.hello(["inputAvailable": true, "inputStatus": "future_state", "platform": "future_os"])!
        check("unknown state fails closed", !unknown.inputAvailable && unknown.platform == .unknown)
        check("missing availability rejected", ReceiverState.hello([:]) == nil)
        print("PASS \(passed) receiver state checks (no device input)")
    }
}
