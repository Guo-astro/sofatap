import Foundation
import Security
import CryptoKit
import Darwin

struct Pairing: Codable, Equatable {
    let host: String
    let port: Int
    let token: String
    let fingerprint: String

    static func parse(_ raw: String) throws -> Pairing {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 2048,
              let url = URLComponents(string: text),
              url.scheme?.lowercased() == "sofatap", url.host == "pair",
              url.user == nil, url.password == nil, url.port == nil,
              url.path.isEmpty, url.fragment == nil,
              let items = url.queryItems, items.count == 4 else { throw PairingError.invalid }
        var fields: [String: String] = [:]
        for item in items {
            guard ["host", "port", "token", "fingerprint"].contains(item.name),
                  fields[item.name] == nil, let value = item.value else { throw PairingError.invalid }
            fields[item.name] = value
        }
        guard let host = fields["host"], validHost(host),
              let portText = fields["port"], portText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let port = Int(portText), (1...65535).contains(port),
              let token = fields["token"], (32...256).contains(token.count),
              token.utf8.allSatisfy({ byte in
                  (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
              }),
              let fingerprint = fields["fingerprint"], fingerprint.utf8.count == 64,
              fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0) })
        else { throw PairingError.invalid }
        return Pairing(host: host.lowercased(), port: port, token: token, fingerprint: fingerprint.lowercased())
    }

    private static func validHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253,
              host.utf8.allSatisfy({ $0 < 128 }) else { return false }
        var address = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 { return true }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
            label.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 })
        }
    }

    var endpoint: URL? {
        var parts = URLComponents()
        parts.scheme = "wss"
        parts.host = host
        parts.port = port
        parts.path = "/control"
        return parts.url
    }
}

enum PairingError: LocalizedError {
    case invalid, storeFailed
    var errorDescription: String? {
        switch self {
        case .invalid: return "配对链接不完整。请复制电脑接收器窗口里的完整 sofatap://pair 链接，或重新扫描二维码。"
        case .storeFailed: return "无法将配对安全保存到钥匙串，请重试。"
        }
    }
}

enum PairingStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.chekusu.sofatap.pairing",
        kSecAttrAccount as String: "living-room-pc"
    ]

    static func read() -> Pairing? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Pairing.self, from: data)
    }

    static func write(_ pairing: Pairing) throws {
        let data = try JSONEncoder().encode(pairing)
        let attributes: [String: Any] = [kSecValueData as String: data,
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var request = query
            attributes.forEach { request[$0.key] = $0.value }
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw PairingError.storeFailed }
        } else if result != errSecSuccess { throw PairingError.storeFailed }
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}

/// Trust is limited to the exact paired host, port and DER leaf fingerprint.
/// The scanned certificate becomes an anchor for this challenge only, never a system CA.
final class PinnedSessionDelegate: NSObject, URLSessionTaskDelegate {
    private let pairing: Pairing
    private let diagnosticLock = NSLock()
    private var failure: String?
    var rejectionReason: String? {
        diagnosticLock.lock(); defer { diagnosticLock.unlock() }
        return failure
    }
    init(pairing: Pairing) { self.pairing = pairing }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Pairing fixes the complete endpoint. Never forward the bearer credential on redirects.
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        func reject(_ reason: String) {
            diagnosticLock.lock(); failure = reason; diagnosticLock.unlock()
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else { reject("TLS_METHOD"); return }
        guard challenge.protectionSpace.host.lowercased() == pairing.host else { reject("TLS_HOST"); return }
        guard challenge.protectionSpace.port == pairing.port else { reject("TLS_PORT_\(challenge.protectionSpace.port)"); return }
        guard let trust = challenge.protectionSpace.serverTrust else { reject("TLS_TRUST_MISSING"); return }
        guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = certificates.first else { reject("TLS_LEAF_MISSING"); return }
        let der = SecCertificateCopyData(leaf) as Data
        let actual = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        guard actual == pairing.fingerprint else {
            reject("TLS_PIN")
            return
        }
        let policyResult = SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, pairing.host as CFString))
        let anchorResult = SecTrustSetAnchorCertificates(trust, [leaf] as CFArray)
        let anchorsOnlyResult = SecTrustSetAnchorCertificatesOnly(trust, true)
        guard policyResult == errSecSuccess, anchorResult == errSecSuccess, anchorsOnlyResult == errSecSuccess else {
            reject("TLS_POLICY_\(policyResult)_\(anchorResult)_\(anchorsOnlyResult)")
            return
        }
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            reject("TLS_VERIFY_\(error.map { CFErrorGetCode($0) } ?? 0)")
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
