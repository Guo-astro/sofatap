import Foundation

@main
struct UnlockProtocolTests {
    static func main() throws {
        var count = 0
        func check(_ name: String, _ result: @autoclosure () -> Bool) throws {
            guard result() else { throw NSError(domain: "UnlockProtocolTests", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
            count += 1
        }
        let fields: [String: Any] = ["version": 1, "port": 53320, "fingerprint": String(repeating: "a", count: 64),
            "token": String(repeating: "A", count: 43), "deviceId": "73441ACB-BA11-4C64-A6CD-014B71D4A088",
            "accountName": "test-local", "accountSid": "S-1-5-21-100-200-300-1001", "provider": "windows-local-password"]
        let capability = UnlockCapability.parse(fields)!
        try check("exact supported service capability", capability.port == 53320)
        try check("device identity normalized", capability.deviceId == "73441acb-ba11-4c64-a6cd-014b71d4a088")
        try check("legacy receiver unsupported", UnlockCapability.parse([:]) == nil)
        for key in fields.keys {
            var changed = fields; changed.removeValue(forKey: key)
            try check("missing capability field \(key)", UnlockCapability.parse(changed) == nil)
        }
        let badFields: [(String, Any)] = [("host", "attacker.example"), ("port", 443), ("port", true),
            ("version", true), ("version", 2), ("fingerprint", String(repeating: "A", count: 64)),
            ("fingerprint", "short"), ("token", String(repeating: "a", count: 42)),
            ("token", String(repeating: "+", count: 43)), ("deviceId", "bad"), ("deviceId", "00000000-0000-0000-0000-000000000000"),
            ("token", String(repeating: "b", count: 43)), ("accountName", "DOMAIN\\user"),
            ("accountSid", "S-1-5-21-9999999999-200-300-1001"),
            ("accountName", "bad\nname"), ("accountSid", "S-1-5-18"), ("provider", "password-injection")]
        for (key, value) in badFields {
            var changed = fields; changed[key] = value
            try check("reject bad capability \(key)", UnlockCapability.parse(changed) == nil)
        }
        let pairing = Pairing(host: "192.0.2.1", port: 53319, token: String(repeating: "c", count: 43), fingerprint: String(repeating: "d", count: 64))
        let binding = capability.binding(pairing)
        try check("service host derives from pairing", capability.servicePairing(pairing).host == pairing.host)
        try check("dedicated pin", capability.servicePairing(pairing).fingerprint == capability.fingerprint)
        try check("dedicated credential token", capability.servicePairing(pairing).token != pairing.token)
        try check("credential binding matches pairing", binding.matches(pairing))
        let rotated = Pairing(host: pairing.host, port: pairing.port, token: String(repeating: "e", count: 43), fingerprint: pairing.fingerprint)
        try check("pairing token rotation revokes binding", !binding.matches(rotated))
        try check("pairing token rotation changes key", binding.storageKey != capability.binding(rotated).storageKey)
        let otherBinding = UnlockCredentialBinding(pairing: pairing, serviceFingerprint: capability.fingerprint,
            deviceID: capability.deviceId, accountID: "S-1-5-21-100-200-300-1002", accountName: capability.accountName, accountProvider: capability.provider)
        try check("account SID has independent item", binding.storageKey != otherBinding.storageKey)
        let newPin = UnlockCredentialBinding(pairing: pairing, serviceFingerprint: String(repeating: "f", count: 64),
            deviceID: capability.deviceId, accountID: capability.accountSid, accountName: capability.accountName, accountProvider: capability.provider)
        try check("login certificate rotation has independent item", binding.storageKey != newPin.storageKey)
        var microsoftFields = fields
        microsoftFields["provider"] = "windows-microsoft-password"
        let microsoft = UnlockCapability.parse(microsoftFields)!
        try check("explicit personal MSA password capability", microsoft.isMicrosoftAccount)
        try check("MSA keeps enrolled Windows SAM alias", microsoft.accountName == capability.accountName)
        try check("account kind cannot reuse local password item", microsoft.binding(pairing).storageKey != binding.storageKey)
        try check("MSA password is not a Hello PIN", microsoft.passwordHint.contains("Windows Hello PIN"))
        try check("MSA passwordless unsupported explained", microsoft.passwordHint.contains("无密码 Microsoft 账户暂不支持"))
        try check("local kind remains local", !capability.isMicrosoftAccount)
        microsoftFields["accountName"] = "person@example.com"
        try check("wire alias must not silently become email", UnlockCapability.parse(microsoftFields) == nil)
        microsoftFields = fields; microsoftFields["provider"] = "windows-entra-password"
        try check("enterprise identity excluded", UnlockCapability.parse(microsoftFields) == nil)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var challenge: [String: Any] = ["deviceId": capability.deviceId, "accountSid": capability.accountSid,
            "attemptId": "CC970911-4474-4A6B-B36F-07DB7B82979A", "nonce": String(repeating: "A", count: 43),
            "expiresAt": format.string(from: now.addingTimeInterval(30)), "sessionId": 1]
        try check("fresh challenge accepted", UnlockChallenge.parse(challenge, capability: capability, now: now) != nil)
        for (key, value) in [("accountSid", "S-1-5-21-100-200-300-1002"), ("deviceId", UUID().uuidString),
                             ("attemptId", "bad/id"), ("nonce", String(repeating: "a", count: 64)),
                             ("expiresAt", format.string(from: now)), ("expiresAt", format.string(from: now.addingTimeInterval(3600)))] {
            var bad = challenge; bad[key] = value
            try check("reject mismatched/stale challenge \(key)", UnlockChallenge.parse(bad, capability: capability, now: now) == nil)
        }
        var windowsTimestamp = challenge
        windowsTimestamp["expiresAt"] = "2027-01-15T08:00:30.1234567+00:00"
        try check(".NET DateTimeOffset seven fractional digits", UnlockChallenge.parse(windowsTimestamp, capability: capability, now: now) != nil)
        challenge["sessionId"] = true
        try check("boolean session rejected", UnlockChallenge.parse(challenge, capability: capability, now: now) == nil)
        challenge["sessionId"] = -1
        try check("negative session rejected", UnlockChallenge.parse(challenge, capability: capability, now: now) == nil)
        try check("waiting is not success", ComputerUnlockState.waiting != .unlocked && ComputerUnlockState.waiting.busy)
        try check("unknown explicitly described", ComputerUnlockState.uncertain.message.contains("不会自动重发"))
        print("Passed \(count) unlock identity and challenge checks; no credentials or biometric prompts used.")
    }
}
