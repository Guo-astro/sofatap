import Foundation
import CryptoKit
import LocalAuthentication
import Security

/// Secrets never share the pairing-token item, draft store, or clipboard.
/// Swift/String and Security.framework may make temporary copies; reset owned
/// Data buffers promptly, but do not claim that all runtime copies are zeroized.
struct UnlockCredentialBinding: Codable, Equatable {
    let host: String
    let port: Int
    let certificateFingerprint: String
    let pairingTokenDigest: String
    let serviceFingerprint: String
    let deviceID: String
    let accountID: String
    let accountName: String
    let accountProvider: String

    init(pairing: Pairing, serviceFingerprint: String = "", deviceID: String = "", accountID: String, accountName: String, accountProvider: String = "") {
        host = pairing.host; port = pairing.port
        certificateFingerprint = pairing.fingerprint
        pairingTokenDigest = SHA256.hash(data: Data(pairing.token.utf8)).map { String(format: "%02x", $0) }.joined()
        self.serviceFingerprint = serviceFingerprint; self.deviceID = deviceID
        self.accountID = accountID; self.accountName = accountName; self.accountProvider = accountProvider
    }

    func matches(_ pairing: Pairing) -> Bool {
        host == pairing.host && port == pairing.port && certificateFingerprint == pairing.fingerprint &&
        pairingTokenDigest == SHA256.hash(data: Data(pairing.token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var storageKey: String {
        // Length-prefixed fields are deterministic and cannot collide through
        // separators embedded in an account name; there is no error fallback key.
        let fields = [host, String(port), certificateFingerprint, pairingTokenDigest,
                      serviceFingerprint, deviceID, accountID, accountName, accountProvider]
        let bytes = Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

enum UnlockVaultError: LocalizedError {
    case faceIDRequired, cancelled, unavailable, missing, saveFailed, invalidPassword
    var errorDescription: String? {
        switch self {
        case .faceIDRequired: return "请先在 iPhone 设置中启用 Face ID 和设备密码。此功能仅使用 Face ID 验证。"
        case .cancelled: return "Face ID 已取消，计算机密码没有发送。"
        case .unavailable: return "Face ID 验证未完成，计算机密码没有发送。请解锁 iPhone 后重试。"
        case .missing: return "未找到可用密码。如果 Face ID 录入已更改，请移除旧记录后重新保存。"
        case .saveFailed: return "密码没有保存，请检查 Face ID 和设备密码设置后重试。"
        case .invalidPassword: return "请输入计算机账户密码（不是 Windows Hello PIN）。"
        }
    }
}

@MainActor
final class UnlockCredentialVault {
    private static let passwordService = "com.chekusu.sofatap.windows-unlock.password.v1"
    private static let bindingService = "com.chekusu.sofatap.windows-unlock.binding.v1"
    private var activeContext: LAContext?

    func cancel() { activeContext?.invalidate(); activeContext = nil }

    /// Metadata can be read without releasing a password or showing Face ID.
    func binding(for pairing: Pairing) -> UnlockCredentialBinding? {
        var query = Self.metadataQuery(pairing)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let metadataContext = LAContext(); metadataContext.interactionNotAllowed = true
        defer { metadataContext.invalidate() }
        query[kSecUseAuthenticationContext as String] = metadataContext
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let bytes = result as? Data,
              let binding = try? JSONDecoder().decode(UnlockCredentialBinding.self, from: bytes),
              binding.matches(pairing) else { return nil }
        return binding
    }

    func save(_ password: inout Data, binding: UnlockCredentialBinding, pairing: Pairing) async throws {
        guard binding.matches(pairing), !password.isEmpty, password.count <= 4096,
              !password.contains(0), let decoded = String(data: password, encoding: .utf8), decoded.utf16.count <= 1024 else {
            throw UnlockVaultError.invalidPassword
        }
        let context = try makeContext()
        defer { context.invalidate(); if activeContext === context { activeContext = nil } }
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "允许 Sofatap 将此电脑密码保存到仅本机、受 Face ID 保护的钥匙串") else {
                throw UnlockVaultError.unavailable
            }
        } catch { throw Self.safeError(error) }
        try Task.checkCancellation()
        guard activeContext === context else { throw UnlockVaultError.cancelled }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                                           .biometryCurrentSet, &error) else {
            throw UnlockVaultError.saveFailed
        }
        // Replacement is explicit and never silently weakens the old ACL.
        let previous = self.binding(for: pairing)
        let secretQuery = Self.secretQuery(binding)
        SecItemDelete(secretQuery as CFDictionary)
        var insert = secretQuery
        insert[kSecValueData as String] = password
        insert[kSecAttrAccessControl as String] = access
        insert[kSecAttrSynchronizable as String] = false
        insert[kSecUseAuthenticationContext as String] = context
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw UnlockVaultError.saveFailed }
        var metadata = Self.metadataQuery(pairing)
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(binding),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false]
        let updated = SecItemUpdate(metadata as CFDictionary, attributes as CFDictionary)
        let result: OSStatus
        if updated == errSecItemNotFound {
            attributes.forEach { metadata[$0.key] = $0.value }
            result = SecItemAdd(metadata as CFDictionary, nil)
        } else { result = updated }
        guard result == errSecSuccess else {
            SecItemDelete(secretQuery as CFDictionary)
            throw UnlockVaultError.saveFailed
        }
        if let previous, previous.storageKey != binding.storageKey { SecItemDelete(Self.secretQuery(previous) as CFDictionary) }
    }

    /// A fresh context plus a biometryCurrentSet-only ACL gives each release its
    /// own biometric prompt. There is no userPresence/devicePasscode OR clause.
    func read(_ binding: UnlockCredentialBinding) async throws -> Data {
        let context = try makeContext()
        defer { context.invalidate(); if activeContext === context { activeContext = nil } }
        var query = Self.secretQuery(binding)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        context.localizedReason = "通过 Face ID 解锁 \(binding.host) 的 \(binding.accountName) 账户"
        let result: (OSStatus, Data?) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var value: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &value)
                continuation.resume(returning: (status, value as? Data))
            }
        }
        var bytes = result.1 ?? Data()
        guard !Task.isCancelled, activeContext === context else {
            bytes.resetBytes(in: 0..<bytes.count); throw UnlockVaultError.cancelled
        }
        guard result.0 == errSecSuccess, !bytes.isEmpty else {
            bytes.resetBytes(in: 0..<bytes.count)
            if result.0 == errSecItemNotFound { throw UnlockVaultError.missing }
            if result.0 == errSecUserCanceled { throw UnlockVaultError.cancelled }
            throw UnlockVaultError.unavailable
        }
        return bytes
    }

    func remove(for pairing: Pairing) {
        cancel()
        if let binding = binding(for: pairing) { SecItemDelete(Self.secretQuery(binding) as CFDictionary) }
        SecItemDelete(Self.metadataQuery(pairing) as CFDictionary)
    }

    private func makeContext() throws -> LAContext {
        cancel()
        let context = LAContext()
        context.localizedFallbackTitle = ""
        context.localizedCancelTitle = "取消"
        context.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              context.biometryType == .faceID else {
            context.invalidate(); throw UnlockVaultError.faceIDRequired
        }
        activeContext = context
        return context
    }

    private static func safeError(_ error: Error) -> UnlockVaultError {
        let code = (error as? LAError)?.code
        if code == .userCancel || code == .appCancel || code == .systemCancel { return .cancelled }
        return .unavailable
    }

    private static func secretQuery(_ binding: UnlockCredentialBinding) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: passwordService,
         kSecAttrAccount as String: binding.storageKey]
    }
    private static func metadataQuery(_ pairing: Pairing) -> [String: Any] {
        let identity = UnlockCredentialBinding(pairing: pairing, accountID: "", accountName: "")
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: bindingService,
                kSecAttrAccount as String: identity.storageKey]
    }
}
