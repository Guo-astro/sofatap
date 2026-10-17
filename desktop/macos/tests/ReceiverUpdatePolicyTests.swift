import Foundation

@main
enum ReceiverUpdatePolicyTests {
    static func main() {
        var count = 0
        func expect(_ value: Bool, _ message: String) {
            count += 1
            precondition(value, message)
        }
        func allowed(_ args: [String] = [], _ path: String = "/Applications/Sofatap Receiver.app",
                     _ id: String? = "com.chekusu.sofatap.receiver", store: Bool = false, fixture: Bool = false) -> Bool {
            ReceiverUpdatePolicy.allowsUpdater(arguments: args, bundlePath: path, bundleIdentifier: id,
                isStore: store, isFixture: fixture)
        }
        expect(allowed(), "Packaged website app may check")
        for args in [["--dry-run"], ["--test-display-id", "9"], ["--test-display-id=9"], ["--test-display-id-invalid"]] {
            expect(!allowed(args), "QA cannot start updater")
        }
        expect(!allowed([], "/tmp/SofaTap"), "Raw CLI cannot start updater")
        expect(!allowed([], "/tmp/Test.app", nil), "Unknown bundle cannot start updater")
        expect(!allowed([], "/tmp/Test.app", "test"), "Other app cannot start updater")
        expect(!allowed(store: true), "App Store manages its updates")
        expect(!allowed(fixture: true), "Fixtures cannot check updates")
        for connected: Bool? in [nil, false, true] {
            for starting in [false, true] {
                for stopping in [false, true] {
                    expect(ReceiverUpdatePolicy.mayResumeInstall(connected: connected, isStarting: starting, isStopping: stopping)
                        == (connected == false && !starting && !stopping), "Restart only known idle receiver")
                }
            }
        }
        expect(ReceiverUpdatePolicy.allowedChannels(releaseVersion: "0.8.0-beta.1") == ["beta"], "Beta may receive beta updates")
        expect(ReceiverUpdatePolicy.allowedChannels(releaseVersion: "0.8.0") == [], "Stable excludes beta")
        expect(ReceiverUpdatePolicy.allowedChannels(releaseVersion: nil) == [], "Unknown channel stays stable")
        print("Passed \(count) receiver update policy checks (no UI, network, registration or installation).")
    }
}
