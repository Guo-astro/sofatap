import Foundation
import Security

struct WebOSTVPairing: Codable, Equatable {
    let host: String
    let fingerprint: String
    let clientKey: String
}

protocol WebOSTVPairingStorage {
    func read() -> WebOSTVPairing?
    func write(_ pairing: WebOSTVPairing) throws
    func delete() throws
}

struct WebOSTVKeychain: WebOSTVPairingStorage {
    private var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.chekusu.sofatap.webos",
        kSecAttrAccount as String: "paired-television"
    ] }
    private enum StoreError: Error { case unavailable }
    func read() -> WebOSTVPairing? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let pairing = try? JSONDecoder().decode(WebOSTVPairing.self, from: data),
              (try? WebOSTVEndpoint(host: pairing.host)) != nil,
              pairing.fingerprint.count == 64,
              pairing.fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              (try? WebOSTVProtocol.registration(id: "validate", clientKey: pairing.clientKey)) != nil else { return nil }
        return pairing
    }
    func write(_ pairing: WebOSTVPairing) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(pairing),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var request = query
            attributes.forEach { request[$0.key] = $0.value }
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw StoreError.unavailable }
        } else if status != errSecSuccess { throw StoreError.unavailable }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.unavailable }
    }
}
