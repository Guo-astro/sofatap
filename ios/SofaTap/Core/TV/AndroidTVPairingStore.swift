import Foundation
import Security

protocol AndroidTVPairingStorage {
    func read() -> AndroidTVPairing?
    func write(_ pairing: AndroidTVPairing) throws
    func delete() throws
}

struct AndroidTVKeychain: AndroidTVPairingStorage {
    private var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.chekusu.sofatap.androidtv",
        kSecAttrAccount as String: "paired-television"
    ] }
    private enum StoreError: Error { case unavailable }
    func read() -> AndroidTVPairing? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let pairing = try? JSONDecoder().decode(AndroidTVPairing.self, from: data),
              (try? pairing.validate()) != nil else { return nil }
        return pairing
    }
    func write(_ pairing: AndroidTVPairing) throws {
        try pairing.validate()
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(pairing),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
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
