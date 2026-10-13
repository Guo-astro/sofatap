import Foundation
import Security

struct WebOSTVPairing: SavedDeviceCredential {
    let host: String
    let fingerprint: String
    let clientKey: String
}

protocol WebOSTVPairingStorage {
    func read() -> WebOSTVPairing?
    func write(_ pairing: WebOSTVPairing) throws
    func delete() throws
    func library() throws -> DeviceLibrary<WebOSTVPairing>
    func select(_ id: UUID) throws
    func rename(_ id: UUID, name: String) throws
    func metadata(_ id: UUID, name: String?, platform: String) throws
    func remove(_ id: UUID) throws
}

extension WebOSTVPairing {
    var deviceIdentity: String { "webos:" + host + ":" + fingerprint }
    var deviceAddress: String { host }
    func validateForStorage() throws { guard (try? WebOSTVEndpoint(host: host)) != nil, fingerprint.count == 64,
              fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              (try? WebOSTVProtocol.registration(id: "validate", clientKey: clientKey)) != nil
        else { throw DeviceLibraryError.invalidData } }
}

// Defaults keep injected single-device test stores compatible. Production uses
// the complete Keychain collection implementation below.
extension WebOSTVPairingStorage {
    func library() throws -> DeviceLibrary<WebOSTVPairing> {
        var library = DeviceLibrary<WebOSTVPairing>()
        if let value = read() { library.upsert(value) }
        return library
    }
    func select(_ id: UUID) throws {
        guard let device = try library().devices.first(where: { $0.id == id }) else { throw DeviceLibraryError.missingDevice }
        try write(device.credential)
    }
    func rename(_ id: UUID, name: String) throws { throw DeviceLibraryError.unavailable }
    func metadata(_ id: UUID, name: String?, platform: String) throws {}
    func remove(_ id: UUID) throws {
        if try library().selectedID == id { try delete() }
    }
}

struct WebOSTVKeychain: WebOSTVPairingStorage {
    private let store = KeychainDeviceLibrary<WebOSTVPairing>(service: "com.chekusu.sofatap.webos", legacyAccount: "paired-television")
    func read() -> WebOSTVPairing? { (try? store.read())?.selected?.credential }
    func library() throws -> DeviceLibrary<WebOSTVPairing> { try store.read() }
    func write(_ pairing: WebOSTVPairing) throws { try store.mutate { $0.upsert(pairing) } }
    func select(_ id: UUID) throws { try store.mutate { try $0.select(id) } }
    func rename(_ id: UUID, name: String) throws { try store.mutate { try $0.rename(id, name: name) } }
    func metadata(_ id: UUID, name: String?, platform: String) throws {
        try store.mutate { try $0.updateMetadata(id, name: name, platform: platform) }
    }
    func remove(_ id: UUID) throws { try store.mutate { $0.remove(id) } }
    func delete() throws {
        try store.mutate { library in
            if let id = library.selectedID { library.remove(id) }
        }
    }
}
