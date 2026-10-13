import Foundation

private final class MemoryDataStore: DeviceLibraryDataStorage {
    var values: [String: Data] = [:]
    var failRead = false
    var failWrite = false
    func read(account: String) throws -> Data? {
        if failRead { throw DeviceLibraryError.unavailable }
        return values[account]
    }
    func write(_ data: Data, account: String) throws {
        if failWrite { throw DeviceLibraryError.unavailable }
        values[account] = data
    }
    func remove(account: String) { values.removeValue(forKey: account) }
}

private final class TVLibraryStore: AndroidTVPairingStorage {
    var value = DeviceLibrary<AndroidTVPairing>()
    var failReadAfterSelection = false
    func read() -> AndroidTVPairing? { value.selected?.credential }
    func write(_ pairing: AndroidTVPairing) throws { value.upsert(pairing) }
    func delete() throws { if let id = value.selectedID { value.remove(id) } }
    func library() throws -> DeviceLibrary<AndroidTVPairing> {
        if failReadAfterSelection { throw DeviceLibraryError.unavailable }
        return value
    }
    func select(_ id: UUID) throws { try value.select(id) }
    func rename(_ id: UUID, name: String) throws { try value.rename(id, name: name) }
    func metadata(_ id: UUID, name: String?, platform: String) throws { try value.updateMetadata(id, name: name, platform: platform) }
    func remove(_ id: UUID) throws { value.remove(id) }
}

@MainActor private final class TVRecordingSocket: AndroidTVSocket {
    var onText: ((String) -> Void)?
    var onFailure: (() -> Void)?
    var opened: AndroidTVPairing?
    var frames: [[String: Any]] = []
    var closes = 0
    func open(_ pairing: AndroidTVPairing) { opened = pairing }
    func send(_ text: String, completion: @escaping (Bool) -> Void) {
        frames.append(try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any])
        completion(true)
    }
    func close() { closes += 1 }
    func hello(_ name: String) {
        reply(["type": "hello", "version": 1, "platform": "androidtv", "name": name,
               "inputAvailable": true, "inputStatus": "ready",
               "capabilities": ["overlayCursor": true, "nodeClick": true, "scroll": true, "back": true, "home": true,
                                "directionalFocus": true, "text": false, "rawMouse": false, "rightClick": false, "drag": false]])
    }
    func reply(_ value: [String: Any]) {
        onText?(String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)!)
    }
}

@main struct SavedDeviceTests {
    @MainActor static func main() throws {
        var count = 0
        func check(_ label: String, _ value: @autoclosure () -> Bool) {
            guard value() else { fatalError("FAIL: \(label)") }
            count += 1
        }
        func rejects(_ label: String, _ action: () throws -> Void) {
            do { try action(); fatalError("FAIL: \(label)") }
            catch { count += 1 }
        }
        let a = Pairing(host: "192.168.1.2", port: 53317, token: String(repeating: "a", count: 43), fingerprint: String(repeating: "a", count: 64))
        let b = Pairing(host: "192.168.1.3", port: 53317, token: String(repeating: "b", count: 43), fingerprint: String(repeating: "b", count: 64))
        let storage = MemoryDataStore()
        storage.values["legacy"] = try JSONEncoder().encode(a)
        let store = KeychainDeviceLibrary<Pairing>(service: "fixture", legacyAccount: "legacy", storage: storage)
        storage.failWrite = true
        rejects("failed migration leaves legacy available") { _ = try store.read() }
        check("failed migration never removes legacy", storage.values["legacy"] != nil && storage.values["paired-devices-v2"] == nil)
        storage.failWrite = false
        let migrated = try store.read()
        check("single pairing migrates selected and intact", migrated.devices.count == 1 && migrated.selected?.credential == a)
        check("migration persists replacement before removing legacy", storage.values["legacy"] == nil && storage.values["paired-devices-v2"] != nil)
        let idA = migrated.selectedID!
        try store.mutate { try $0.rename(idA, name: "  Living room  ") }
        try store.mutate { try $0.updateMetadata(idA, name: "GAMING-PC", platform: "windows") }
        try store.mutate { $0.upsert(b) }
        let both = try store.read()
        let idB = both.selectedID!
        check("adding second device preserves first and selects second", both.devices.count == 2 && both.selected?.credential == b)
        check("alias wins without overwriting reported name", both.devices.first?.displayName == "Living room" && both.devices.first?.reportedName == "GAMING-PC")
        let refreshed = Pairing(host: "192.168.1.50", port: 53318, token: String(repeating: "c", count: 43), fingerprint: a.fingerprint)
        try store.mutate { $0.upsert(refreshed) }
        let refreshedLibrary = try store.read()
        check("token and address refresh preserve stable device and alias", refreshedLibrary.devices.count == 2 && refreshedLibrary.selectedID == idA && refreshedLibrary.selected?.displayName == "Living room")
        check("refresh updates only the intended credential", refreshedLibrary.selected?.credential == refreshed && refreshedLibrary.devices.last?.credential == b)
        try store.mutate { $0.remove(idB) }
        let removedInactive = try store.read()
        check("inactive removal leaves selection untouched", removedInactive.selectedID == idA && removedInactive.devices.count == 1)
        try store.mutate { $0.upsert(b) }
        try store.mutate { $0.remove(idB) }
        let removedActive = try store.read()
        check("active removal does not fall back to remaining device", removedActive.devices.count == 1 && removedActive.selectedID == nil)
        rejects("select missing device fails") { try store.mutate { try $0.select(idB) } }
        let unmodified = storage.values
        rejects("control characters in name rejected") { try store.mutate { try $0.rename(idA, name: "Living\nroom") } }
        rejects("oversize name rejected") { try store.mutate { try $0.rename(idA, name: String(repeating: "x", count: 81)) } }
        check("invalid updates preserve persisted data", storage.values == unmodified)
        try store.mutate { try $0.rename(idA, name: " ") }
        let noAlias = try store.read()
        check("empty alias resets to receiver name", noAlias.devices.first?.displayName == "GAMING-PC")
        try store.mutate { $0.remove(idA) }
        storage.values["legacy"] = try JSONEncoder().encode(a)
        let noResurrection = try store.read()
        check("empty library prevents legacy resurrection", noResurrection.devices.isEmpty)
        storage.failRead = true
        let beforeFailedRead = storage.values
        rejects("locked or unreadable Keychain cannot be overwritten") { try store.mutate { $0.upsert(b) } }
        check("read failure retains all persisted bytes", storage.values == beforeFailedRead)
        storage.failRead = false
        storage.values["paired-devices-v2"] = Data("corrupt".utf8)
        rejects("corrupt collection does not silently replace legacy") { _ = try store.read() }
        check("corrupt collection remains available for recovery", storage.values["paired-devices-v2"] == Data("corrupt".utf8))

        let tv = AndroidTVPairing(host: "192.168.1.2", port: 53319, token: a.token, fingerprint: a.fingerprint)
        let androidID = SavedDevice(credential: tv).id
        check("computer and Android TV identities cannot collide", androidID != idA)
        check("Android TV renewed token retains identity", androidID == SavedDevice(credential: tv.replacingToken(b.token)).id)
        let webA = WebOSTVPairing(host: "192.168.1.2", fingerprint: a.fingerprint, clientKey: "fixture-client-key")
        let webB = WebOSTVPairing(host: "192.168.1.3", fingerprint: a.fingerprint, clientKey: "fixture-other-key")
        check("webOS shared certificates do not merge different TV endpoints", SavedDevice(credential: webA).id != SavedDevice(credential: webB).id)
        try tv.validateForStorage(); try webA.validateForStorage()

        let tvB = AndroidTVPairing(host: "192.168.1.3", port: 53319, token: b.token, fingerprint: b.fingerprint)
        let tvStore = TVLibraryStore()
        tvStore.value.upsert(tv); tvStore.value.upsert(tvB)
        let tvBID = SavedDevice(credential: tvB).id
        var sockets: [TVRecordingSocket] = []
        let controller = AndroidTVController(storage: tvStore, makeSocket: {
            let socket = TVRecordingSocket(); sockets.append(socket); return socket
        })
        controller.selectDevice(tvBID)
        let socketB = sockets.last!
        check("saved selection opens only exact selected TV credential", socketB.opened == tvB && sockets.count == 1)
        socketB.hello("Bedroom TV")
        controller.move(dx: 5, dy: 3); controller.click()
        check("old target has one outstanding input and queued click", socketB.frames.count == 1)
        controller.selectDevice(androidID)
        let socketA = sockets.last!
        socketB.reply(["type": "ack", "id": socketB.frames[0]["id"]!, "ok": true])
        socketA.hello("Living room TV")
        check("switch closes prior TV and cannot replay queued click to new TV", socketB.closes == 1 && socketA.opened == tv && socketA.frames.isEmpty && controller.canControl)
        controller.renameDevice(tvBID, name: "Guest room")
        check("rename inactive TV does not change active transport", controller.selectedDeviceID == androidID && controller.currentDisplayName == "Living room TV" && sockets.count == 2)
        controller.renameDevice(androidID, name: "  Cinema  ")
        check("active rename updates display immediately with same credential", controller.currentDisplayName == "Cinema" && controller.saved == tv)
        controller.renameDevice(androidID, name: "invalid\nname")
        check("name failure exposes error without interrupting valid session", controller.managementError != nil && controller.canControl && controller.currentDisplayName == "Cinema")
        controller.removeDevice(androidID)
        check("active TV removal disconnects without falling back to saved TV", controller.saved == nil && controller.selectedDeviceID == nil && controller.savedDevices.count == 1 && !controller.canControl)
        controller.reconnect()
        check("reconnect with no selected device cannot pick another TV", sockets.count == 2)
        controller.selectDevice(tvBID); sockets.last!.hello("Bedroom TV")
        tvStore.failReadAfterSelection = true
        controller.selectDevice(tvBID)
        check("collection read failure after selecting never reconnects cached old target", !controller.canControl && controller.managementError != nil && sockets.count == 3)
        print("PASS \(count) saved-device migration, selection, privacy and persistence checks; no Keychain, network or input access")
    }
}
