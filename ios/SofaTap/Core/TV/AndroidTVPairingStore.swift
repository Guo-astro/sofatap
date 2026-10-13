import Foundation
import Security

protocol AndroidTVPairingStorage {
    func read() -> AndroidTVPairing?
    func write(_ pairing: AndroidTVPairing) throws
    func delete() throws
    func library() throws -> DeviceLibrary<AndroidTVPairing>
    func select(_ id: UUID) throws
    func rename(_ id: UUID, name: String) throws
    func metadata(_ id: UUID, name: String?, platform: String) throws
    func remove(_ id: UUID) throws
}

extension AndroidTVPairing: SavedDeviceCredential {
    var deviceIdentity: String { "androidtv:" + fingerprint }
    var deviceAddress: String { "\(host):\(port)" }
    var pairingName: String? { name }
    var pairingPlatform: String? { platform ?? "androidtv" }
    func validateForStorage() throws { try validate() }
}

// Defaults keep injected single-device test stores compatible. Production uses
// the complete Keychain collection implementation below.
extension AndroidTVPairingStorage {
    func library() throws -> DeviceLibrary<AndroidTVPairing> {
        var library = DeviceLibrary<AndroidTVPairing>()
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

struct AndroidTVKeychain: AndroidTVPairingStorage {
    private let store = KeychainDeviceLibrary<AndroidTVPairing>(service: "com.chekusu.sofatap.androidtv", legacyAccount: "paired-television")
    func read() -> AndroidTVPairing? { (try? store.read())?.selected?.credential }
    func library() throws -> DeviceLibrary<AndroidTVPairing> { try store.read() }
    func write(_ pairing: AndroidTVPairing) throws { try store.mutate { $0.upsert(pairing) } }
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
