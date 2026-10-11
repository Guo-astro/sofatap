import Foundation
import CoreFoundation

/// Legacy account-password experiment, retained for compatibility review and
/// binding tests only. The app controller rejects it; it is not a Hello PIN API.
struct UnlockCapability: Codable, Equatable {
    let version: Int
    let port: Int
    let fingerprint: String
    let token: String
    let deviceId: String
    let accountName: String
    let accountSid: String
    let provider: String
    var isMicrosoftAccount: Bool { provider == "windows-microsoft-password" }
    var accountTypeLabel: String { isMicrosoftAccount ? "个人 Microsoft 账户" : "Windows 本地账户" }
    var passwordLabel: String { isMicrosoftAccount ? "Microsoft 账户密码" : "计算机账户密码" }
    var passwordHint: String {
        isMicrosoftAccount
            ? "请输入与此 Windows 用户关联的个人 Microsoft 账户密码，不能使用 Windows Hello PIN。无密码 Microsoft 账户暂不支持。"
            : "请输入此 Windows 本地账户的密码，不能使用 Windows Hello PIN。"
    }

    static func parse(_ object: [String: Any]) -> UnlockCapability? {
        let fields: Set<String> = ["version", "port", "fingerprint", "token", "deviceId", "accountName", "accountSid", "provider"]
        guard Set(object.keys) == fields, integer(object["version"]) == 1,
              integer(object["port"]) == 53320,
              let fingerprint = object["fingerprint"] as? String, hex(fingerprint, count: 64),
              let token = object["token"] as? String, opaque(token),
              let device = object["deviceId"] as? String, let deviceUUID = UUID(uuidString: device),
              deviceUUID.uuidString != "00000000-0000-0000-0000-000000000000",
              let name = object["accountName"] as? String, !name.isEmpty, name.utf16.count <= 104,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.contains("\\"), !name.contains("/"), !name.contains("@"),
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              let sid = object["accountSid"] as? String,
              sid.range(of: #"^S-1-5-21-[0-9]{1,10}-[0-9]{1,10}-[0-9]{1,10}-[0-9]{1,10}$"#, options: .regularExpression) != nil,
              sid.split(separator: "-").dropFirst(4).allSatisfy({ UInt32($0) != nil }),
              let provider = object["provider"] as? String,
              ["windows-local-password", "windows-microsoft-password"].contains(provider) else { return nil }
        return UnlockCapability(version: 1, port: 53320, fingerprint: fingerprint, token: token,
                                deviceId: device.lowercased(), accountName: name, accountSid: sid,
                                provider: provider)
    }

    func binding(_ pairing: Pairing) -> UnlockCredentialBinding {
        UnlockCredentialBinding(pairing: pairing, serviceFingerprint: fingerprint, deviceID: deviceId,
                                accountID: accountSid, accountName: accountName, accountProvider: provider)
    }
    func servicePairing(_ pairing: Pairing) -> Pairing {
        Pairing(host: pairing.host, port: port, token: token, fingerprint: fingerprint)
    }
    func validates(_ object: [String: Any]) -> Bool {
        (object["deviceId"] as? String)?.lowercased() == deviceId && object["accountSid"] as? String == accountSid
    }
    static func opaque(_ value: String) -> Bool {
        guard value.utf8.count == 43, value.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }), let decoded = Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="),
              decoded.count == 32 else { return false }
        return decoded.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == value
    }
    private static func hex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue >= 0, number.doubleValue <= Double(Int32.max) else { return nil }
        return number.intValue
    }
}

struct UnlockChallenge {
    let attemptID: String
    let nonce: String
    let expiresAt: Date
    let sessionID: Int

    static func parse(_ object: [String: Any], capability: UnlockCapability, now: Date) -> UnlockChallenge? {
        guard capability.validates(object), let attempt = object["attemptId"] as? String, UUID(uuidString: attempt) != nil,
              let nonce = object["nonce"] as? String, UnlockCapability.opaque(nonce),
              let session = UnlockCapability.integer(object["sessionId"]),
              let expiry = object["expiresAt"] as? String else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: expiry) ?? ISO8601DateFormatter().date(from: expiry)
        guard let date, date > now, date.timeIntervalSince(now) <= 35 else { return nil }
        return UnlockChallenge(attemptID: attempt.lowercased(), nonce: nonce, expiresAt: date, sessionID: session)
    }
}

enum ComputerUnlockState: Equatable {
    case idle, checking, authenticating, saving, submitting, waiting, unlocked, rejected, uncertain, failed(String)
    var busy: Bool {
        switch self { case .checking, .authenticating, .saving, .submitting, .waiting: return true; default: return false }
    }
    var message: String {
        switch self {
        case .idle: return "每次解锁均需 Face ID；计算机密码只由 Windows 验证。"
        case .checking: return "正在检查 Windows 登录组件…"
        case .authenticating: return "请通过 Face ID 确认这次解锁。"
        case .saving: return "正在安全保存计算机密码…"
        case .submitting: return "正在将密码加密发送给这台电脑…"
        case .waiting: return "等待 Windows 确认登录结果…"
        case .unlocked: return "Windows 已确认解锁。"
        case .rejected: return "Windows 未接受此密码。请检查账户密码；不会自动重试。"
        case .uncertain: return "尚未确认解锁结果，密码不会自动重发。请先查看电视或电脑屏幕。"
        case .failed(let message): return message
        }
    }
}
