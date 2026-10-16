import Foundation

@main
enum ReceiverLoginItemTests {
    @MainActor static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func model(_ service: FakeService, _ preferences: FakePreferences, available: Bool = true) -> ReceiverLoginItem {
            ReceiverLoginItem(isAvailable: available, service: service, preferences: preferences,
                              firstLaunchPolicy: .automaticRegistration)
        }
        let service = FakeService(), preferences = FakePreferences()
        let first = model(service, preferences)
        check(service.reads == 0 && !preferences.hasConfiguredLoginItem, "constructing UI must not configure the OS")
        first.configureFirstLaunch()
        check(service.registrations == 1 && first.status == .enabled && preferences.hasConfiguredLoginItem,
              "first normal launch enables login startup")
        model(service, preferences).configureFirstLaunch()
        check(service.registrations == 1, "next launch must not register again")
        first.setRequested(false)
        check(service.unregistrations == 1 && first.status == .notRegistered && !first.isRequested, "explicit opt-out")
        model(service, preferences).configureFirstLaunch()
        check(service.registrations == 1, "opt-out survives reopening")
        first.setRequested(true)
        check(service.registrations == 2 && first.status == .enabled, "explicit opt-in restores registration")
        service.current = .notRegistered
        first.refresh()
        check(first.status == .notRegistered && !first.isRequested, "reflect OS removal")
        model(service, preferences).configureFirstLaunch()
        check(service.registrations == 2, "OS removal survives next launch")
        service.current = .requiresApproval
        first.refresh()
        check(first.status == .requiresApproval, "OS revocation is visible as pending, not enabled")
        first.setRequested(true)
        check(service.registrations == 2 && service.unregistrations == 1, "never cycle registration to bypass denial")
        first.setRequested(false)
        check(service.unregistrations == 2 && first.status == .notRegistered, "pending registration can be disabled")

        let existing = FakeService(.requiresApproval), existingPrefs = FakePreferences()
        model(existing, existingPrefs).configureFirstLaunch()
        check(existingPrefs.hasConfiguredLoginItem && existing.registrations == 0,
              "a previously denied or pending login item is respected even without local marker")
        let enabled = FakeService(.enabled)
        model(enabled, FakePreferences()).configureFirstLaunch()
        check(enabled.registrations == 0, "already enabled is not registered twice")

        let failing = FakeService(), failingPrefs = FakePreferences()
        failing.shouldFail = true
        let failure = model(failing, failingPrefs)
        failure.configureFirstLaunch()
        check(failure.failure != nil && failure.status == .notRegistered && !failure.isRequested,
              "registration error never reports enabled")
        model(failing, failingPrefs).configureFirstLaunch()
        check(failing.registrations == 1, "failed default is not retried on each launch")
        failing.shouldFail = false
        failure.setRequested(true)
        check(failure.failure == nil && failure.status == .enabled, "user can explicitly retry a failed registration")
        failing.shouldFail = true
        failure.setRequested(false)
        check(failure.failure != nil && failure.status == .enabled, "failed opt-out keeps actual OS status visible")

        let pending = FakeService()
        pending.registrationResult = .requiresApproval
        let pendingModel = model(pending, FakePreferences())
        pendingModel.configureFirstLaunch()
        check(pendingModel.status == .requiresApproval, "system approval is distinct from success")
        let absent = FakeService(.unavailable)
        let absentModel = model(absent, FakePreferences())
        absentModel.configureFirstLaunch()
        check(absentModel.status == .unavailable && absent.registrations == 0, "missing app is not silently treated as registered")

        let suppressed = FakeService(), suppressedPrefs = FakePreferences()
        let dryRun = model(suppressed, suppressedPrefs, available: false)
        dryRun.configureFirstLaunch()
        dryRun.setRequested(true)
        dryRun.setRequested(false)
        dryRun.refresh()
        check(suppressed.reads == 0 && suppressed.registrations == 0 && suppressed.unregistrations == 0
              && !suppressedPrefs.hasConfiguredLoginItem, "QA mode never reads or changes real startup state")
        let bundle = URL(fileURLWithPath: "/Applications/Sofatap Receiver.app")
        let identifier = "com.chekusu.sofatap.receiver"
        check(ReceiverLoginItem.canManage(arguments: [], bundleIdentifier: identifier, bundleURL: bundle), "production bundle eligible")
        for arguments in [["--dry-run"], ["--dry-run", "--test-display-id", "20"], ["--test-display-id=20"]] {
            check(!ReceiverLoginItem.canManage(arguments: arguments, bundleIdentifier: identifier, bundleURL: bundle), "test launch excluded")
        }
        check(!ReceiverLoginItem.canManage(arguments: [], bundleIdentifier: nil, bundleURL: bundle), "raw compiled executable excluded")
        check(!ReceiverLoginItem.canManage(arguments: [], bundleIdentifier: "fixture", bundleURL: bundle), "different bundle excluded")
        check(!ReceiverLoginItem.canManage(arguments: [], bundleIdentifier: identifier, bundleURL: URL(fileURLWithPath: "/tmp/SofaTap")), "non-app excluded")

        let storeService = FakeService(), storePrefs = FakePreferences()
        let store = ReceiverLoginItem(isAvailable: true, service: storeService, preferences: storePrefs,
                                      firstLaunchPolicy: .explicitConsent)
        store.configureFirstLaunch()
        check(store.needsFirstLaunchConsent && store.firstLaunchRequested && !store.isRequested,
              "store default is an unconfirmed selection, not an active login item")
        check(storeService.registrations == 0 && !storePrefs.hasConfiguredLoginItem,
              "store launch does not register or record consent")
        store.refresh()
        store.configureFirstLaunch()
        check(storeService.registrations == 0 && store.needsFirstLaunchConsent,
              "repeated launch/refresh cannot substitute for consent")
        store.confirmFirstLaunch()
        check(storeService.registrations == 1 && store.isRequested && storePrefs.hasConfiguredLoginItem
              && !store.needsFirstLaunchConsent, "explicit confirmation enables the selected startup choice")
        store.confirmFirstLaunch()
        check(storeService.registrations == 1, "duplicate confirmation cannot re-register")
        store.setRequested(false)
        store.configureFirstLaunch()
        check(storeService.registrations == 1 && !store.isRequested && !store.needsFirstLaunchConsent,
              "store opt-out survives reopening without another prompt")

        let declinedService = FakeService(), declinedPrefs = FakePreferences()
        let declined = ReceiverLoginItem(isAvailable: true, service: declinedService, preferences: declinedPrefs,
                                         firstLaunchPolicy: .explicitConsent)
        declined.configureFirstLaunch()
        declined.firstLaunchRequested = false
        declined.confirmFirstLaunch()
        declined.configureFirstLaunch()
        check(declinedService.registrations == 0 && declinedPrefs.hasConfiguredLoginItem
              && !declined.needsFirstLaunchConsent, "declining setup persists without any OS registration")

        let consentFailService = FakeService(), consentFailPrefs = FakePreferences()
        consentFailService.shouldFail = true
        let consentFailure = ReceiverLoginItem(isAvailable: true, service: consentFailService, preferences: consentFailPrefs,
                                               firstLaunchPolicy: .explicitConsent)
        consentFailure.configureFirstLaunch()
        consentFailure.confirmFirstLaunch()
        consentFailure.configureFirstLaunch()
        check(consentFailure.failure != nil && !consentFailure.isRequested && consentFailService.registrations == 1,
              "failed store consent does not silently retry or claim startup is enabled")

        let knownService = FakeService(.requiresApproval)
        let known = ReceiverLoginItem(isAvailable: true, service: knownService, preferences: FakePreferences(),
                                       firstLaunchPolicy: .explicitConsent)
        known.configureFirstLaunch()
        check(!known.needsFirstLaunchConsent && knownService.registrations == 0 && known.status == .requiresApproval,
              "existing pending system choice is not overridden by first-run onboarding")
        #if SOFATAP_MAC_APP_STORE
        check(ReceiverLoginFirstLaunchPolicy.distributionDefault == .explicitConsent, "store compilation uses explicit consent")
        #else
        check(ReceiverLoginFirstLaunchPolicy.distributionDefault == .automaticRegistration, "website compilation keeps existing behavior")
        #endif
        print("PASS: \(checks) login-start checks (injected services and in-memory preferences; no OS registration, window or receiver)")
    }
}

@MainActor
private final class FakePreferences: ReceiverLoginPreferences {
    var hasConfiguredLoginItem = false
}

@MainActor
private final class FakeService: ReceiverLoginService {
    var current: ReceiverLoginStatus
    var registrationResult: ReceiverLoginStatus = .enabled
    var reads = 0, registrations = 0, unregistrations = 0
    var shouldFail = false
    init(_ initial: ReceiverLoginStatus = .notRegistered) { current = initial }
    var status: ReceiverLoginStatus { reads += 1; return current }
    func register() throws {
        registrations += 1
        if shouldFail { throw Failure.expected }
        current = registrationResult
    }
    func unregister() throws {
        unregistrations += 1
        if shouldFail { throw Failure.expected }
        current = .notRegistered
    }
    private enum Failure: Error { case expected }
}
