// Release verification helper: queries a caller-owned fixture bundle/feed only.
// No NSApplication run loop, receiver, UI, download, or installation is started.
import AppKit
import Sparkle

@MainActor
private final class NoUI: NSObject, SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { fatalError("Unexpected permission UI") }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { cancellation() }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.dismiss) }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { cancellation(); fatalError("Discovery must not download") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { fatalError("Unexpected download") }
    func showDownloadDidReceiveData(ofLength length: UInt64) { fatalError("Unexpected download") }
    func showDownloadDidStartExtractingUpdate() { fatalError("Unexpected extraction") }
    func showExtractionReceivedProgress(_ progress: Double) { fatalError("Unexpected extraction") }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.dismiss); fatalError("Unexpected installation") }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { fatalError("Unexpected installation") }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { fatalError("Unexpected installation") }
    func dismissUpdateInstallation() {}
}

@MainActor
private final class Probe: NSObject, SPUUpdaterDelegate {
    let userDriver = NoUI()
    var updater: SPUUpdater?
    var found: String?
    var finished = false
    var errorCode: Int?
    var errorDomain: String?
    var errorDescription: String?
    var releaseVersion: String?

    func run(bundle: Bundle) throws {
        releaseVersion = bundle.object(forInfoDictionaryKey: "SofatapReleaseVersion") as? String
        updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: userDriver, delegate: self)
        try updater!.start()
        updater!.checkForUpdateInformation()
    }
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        ReceiverUpdatePolicy.allowedChannels(releaseVersion: releaseVersion)
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { found = item.versionString }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        errorDescription = error?.localizedDescription
        errorCode = (error as NSError?)?.code
        errorDomain = (error as NSError?)?.domain
        finished = true
    }
}

@main
private enum Main {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2, let bundle = Bundle(path: CommandLine.arguments[1]),
            let id = bundle.bundleIdentifier, id.hasPrefix("com.chekusu.sofatap.update-probe."),
            let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let url = URL(string: feed), url.scheme == "http", url.host == "127.0.0.1",
            bundle.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool == false,
            bundle.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool == false else {
            fatalError("Only a dedicated, automatic-update-disabled probe bundle is accepted")
        }
        let probe = Probe()
        try probe.run(bundle: bundle)
        let deadline = Date().addingTimeInterval(30)
        while !probe.finished && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        guard probe.finished else { fatalError("Discovery timed out") }
        let result: [String: Any] = ["foundVersion": probe.found ?? NSNull(),
            "errorCode": probe.errorCode as Any? ?? NSNull(), "errorDomain": probe.errorDomain as Any? ?? NSNull(),
            "errorDescription": probe.errorDescription ?? NSNull(), "downloadOrInstall": false]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
        UserDefaults.standard.removePersistentDomain(forName: id)
    }
}
