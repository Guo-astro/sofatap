import Foundation

@main
struct PairingAttemptTests {
    @MainActor static func main() throws {
        var passed = 0
        func check(_ name: String, _ condition: @autoclosure () throws -> Bool) rethrows {
            guard try condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            passed += 1
        }
        let token = String(repeating: "a", count: 43)
        let pinA = String(repeating: "a", count: 64)
        let pinB = String(repeating: "b", count: 64)
        let pcA = "sofatap://pair?host=pc-a.local&port=53317&token=\(token)&fingerprint=\(pinA)"
        let pcB = "sofatap://pair?host=pc-b.local&port=53317&token=\(token)&fingerprint=\(pinB)&name=New%20PC"
        let tv = "sofatap://tv?host=192.168.1.8&port=53318&token=\(token)&fingerprint=\(pinA)"
        let reorderedTV = "SOFATAP://tv?fingerprint=\(pinA.uppercased())&name=New%20label&token=\(token)&port=053318&host=192.168.1.8"
        var attempt = PairingAttemptState()
        try check("valid desktop candidate starts", attempt.begin(pcB))
        check("desktop retry retains the candidate's exact original link", attempt.computerRetryLink == pcB)
        try check("changed metadata/order/case do not restart desktop credentials", !attempt.begin("SOFATAP://pair?token=\(token)&host=PC-B.LOCAL&fingerprint=\(pinB.uppercased())&port=053317&name=Other"))
        check("duplicate desktop delivery does not replace retry source", attempt.computerRetryLink == pcB)
        do { _ = try attempt.begin("https://unrelated.example"); check("invalid QR rejected", false) }
        catch { check("invalid QR preserves the pending candidate", attempt.computerRetryLink == pcB) }
        attempt.markAuthenticated()
        check("successful candidate no longer owns a cancellation or retry", attempt.pendingCandidate == nil && attempt.computerRetryLink == nil)
        try check("successful duplicate does not reset naming", !attempt.begin(pcB) && attempt.authenticated)

        var android = PairingAttemptState()
        var bootstrapConnections: [PairingCode] = []
        check("scanner validation does not consume a fresh bootstrap", android.canBegin(tv) && android.canBegin(reorderedTV) && android.candidate == nil)
        func deliverTV(_ raw: String) throws {
            if try android.begin(raw), let candidate = android.candidate { bootstrapConnections.append(candidate) }
        }
        try deliverTV(tv); try deliverTV(reorderedTV)
        check("camera then canonical pasted/link duplicate opens one pending bootstrap", bootstrapConnections.count == 1)
        android.markAuthenticated(); try deliverTV(reorderedTV)
        check("duplicate while naming preserves authenticated connection", bootstrapConnections.count == 1 && android.authenticated)
        android.resetScanner()
        check("scanner rejects a spent code before stopping capture", !android.canBegin(reorderedTV))
        do { try deliverTV(tv); check("reset must not replay a consumed bootstrap", false) }
        catch { check("reset retains bootstrap attempt history", android.candidate == nil && bootstrapConnections.count == 1) }
        do { try deliverTV(tv.replacingOccurrences(of: "192.168.1.8", with: "192.168.1.9")); check("alias must not replay same token", false) }
        catch { check("same pin and token at another address are not replayed", bootstrapConnections.count == 1) }
        let freshTV = tv.replacingOccurrences(of: "token=\(token)", with: "token=\(String(repeating: "z", count: 43))")
        check("scanner stays able to accept a fresh code after rejecting a spent one", android.canBegin(freshTV))
        try deliverTV(freshTV)
        check("new QR token can start another attempt", bootstrapConnections.count == 2 && !android.authenticated)
        _ = try android.begin(pcA)
        do { try deliverTV(tv); check("switching adapters must not replay an earlier token", false) }
        catch { check("rejected old bootstrap leaves current desktop candidate intact", android.computerRetryLink == pcA) }
        var interrupted = PairingAttemptState(); _ = try interrupted.begin(tv); interrupted.resetScanner()
        do { _ = try interrupted.begin(reorderedTV); check("failed bootstrap must not be retried", false) }
        catch { check("even an unconfirmed bootstrap needs a fresh QR", interrupted.candidate == nil) }

        let old = try Pairing.parse(pcA), new = try Pairing.parse(pcB)
        var library = DeviceLibrary<Pairing>(); library.upsert(old)
        var writes: [Pairing] = [], connections: [Pairing] = []
        var failSave = true
        let model = ControllerModel(testPairingLibrary: library, testPairingWrite: { value in
            writes.append(value)
            if failSave { throw PairingError.storeFailed }
            library.upsert(value); return library
        }, testPairingConnect: { connections.append($0) })
        model.connect()
        check("fixture has an existing connection attempt to A", connections == [old] && model.connecting)
        model.acceptPairing("invalid")
        check("unrelated invalid input cannot cancel an existing target", model.connecting && connections == [old] && writes.isEmpty)
        var desktopFlow = PairingAttemptState(); _ = try desktopFlow.begin(pcB)
        model.acceptPairing(desktopFlow.computerRetryLink!)
        check("failed B save disconnects A and records only candidate B", !model.connected && !model.connecting && model.pairing == old && writes == [new])
        model.becameInactive(); model.becameActive()
        check("failed B save cannot auto-reconnect stored A on foreground", connections == [old] && !model.connecting)
        if case .computer = desktopFlow.pendingCandidate { model.disconnectDevice() }
        model.becameInactive(); model.becameActive()
        check("cancel after save failure keeps old A paused", connections == [old])
        failSave = false
        model.acceptPairing(desktopFlow.computerRetryLink!)
        check("explicit Retry persists original B rather than connecting A", writes == [new, new] && model.pairing == new && connections == [old, new])
        check("retry selects the newly saved device before connecting", model.selectedDeviceID == SavedDevice(credential: new).id)
        model.disconnect(message: "test timeout")
        if case .computer = desktopFlow.pendingCandidate { model.disconnectDevice() }
        model.becameInactive(); model.becameActive()
        check("cancel after timeout prevents foreground reconnection", connections == [old, new] && !model.connecting)
        model.acceptPairing(desktopFlow.computerRetryLink!)
        model.becameInactive()
        if case .computer = desktopFlow.pendingCandidate { model.disconnectDevice() }
        model.becameActive()
        check("cancel after background disconnection remains paused", connections == [old, new, new] && !model.connecting)
        desktopFlow.resetScanner()
        check("rescan relinquishes old retry and pending candidate", desktopFlow.computerRetryLink == nil && desktopFlow.pendingCandidate == nil)
        _ = try desktopFlow.begin(pcA)
        model.acceptPairing(desktopFlow.computerRetryLink!)
        check("a fresh explicit candidate can reconnect after cancellation", model.pairing == old && connections == [old, new, new, old])
        model.disconnectDevice()
        print("Pairing attempt tests: \(passed) passed")
    }
}
