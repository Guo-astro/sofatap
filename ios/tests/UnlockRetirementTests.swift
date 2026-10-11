import Foundation

@main
struct UnlockRetirementTests {
    @MainActor
    static func main() async throws {
        var count = 0
        func check(_ name: String, _ result: @autoclosure () -> Bool) throws {
            guard result() else {
                throw NSError(domain: "UnlockRetirementTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: name])
            }
            count += 1
        }
        let controller = ComputerUnlockController()
        let pairing = Pairing(host: "192.0.2.248", port: 53319,
                              token: String(repeating: "A", count: 43),
                              fingerprint: String(repeating: "f", count: 64))
        // This only reads synthetic binding metadata. It never creates or reads
        // a password item, prompts for biometrics, or performs desktop input.
        controller.setPairing(pairing)
        for provider in ["windows-local-password", "windows-microsoft-password"] {
            let fields: [String: Any] = [
                "version": 1, "port": 53320, "fingerprint": String(repeating: "a", count: 64),
                "token": String(repeating: "A", count: 43),
                "deviceId": "73441acb-ba11-4c64-a6cd-014b71d4a088",
                "accountName": "retirement-test", "accountSid": "S-1-5-21-100-200-300-1001",
                "provider": provider
            ]
            try check("fixture is a valid legacy capability", UnlockCapability.parse(fields) != nil)
            controller.receiveCapability(fields, pairing: pairing)
            try check("valid legacy capability cannot reactivate feature", controller.capability == nil && !controller.supported)
            try check("no account-password affordance enabled", !controller.canEnroll && !controller.canUnlock)
            controller.savePassword(Data("synthetic-retired-secret".utf8))
            controller.unlock()
            await Task.yield()
            try check("public entrypoints cannot start authentication or submission", controller.state == .idle && controller.serviceState == nil)
        }
        controller.becameInactive()
        controller.becameActive()
        controller.setPairing(pairing)
        try check("foreground/reload cannot restore password capability", controller.capability == nil && !controller.canEnroll && !controller.canUnlock)
        controller.setPairing(nil)
        controller.unlock()
        try check("unpaired controller remains idle", controller.state == .idle && controller.pairing == nil)
        let foreignPairing = Pairing(host: "192.0.2.249", port: pairing.port,
                                     token: pairing.token, fingerprint: pairing.fingerprint)
        let foreignBinding = UnlockCredentialBinding(pairing: foreignPairing,
            accountID: "S-1-5-21-100-200-300-1001", accountName: "retirement-test")
        try check("legacy deletion cannot target another paired computer",
                  !UnlockCredentialVault().remove(for: pairing, knownBinding: foreignBinding))
        print("Passed \(count) account-password retirement checks; no credentials, biometric prompts or desktop input used.")
    }
}
