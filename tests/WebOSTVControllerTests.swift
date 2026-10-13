import Foundation
import Combine

private enum FixtureError: Error { case storageUnavailable }

private final class TVMemoryStore: WebOSTVPairingStorage {
    var value: WebOSTVPairing?
    var reads = 0
    var writes: [WebOSTVPairing] = []
    var deletes = 0
    var rejectWrite = false
    init(_ value: WebOSTVPairing? = nil) { self.value = value }
    func read() -> WebOSTVPairing? { reads += 1; return value }
    func write(_ pairing: WebOSTVPairing) throws {
        if rejectWrite { throw FixtureError.storageUnavailable }
        writes.append(pairing); value = pairing
    }
    func delete() throws { deletes += 1; value = nil }
}

@MainActor
private final class TVFakeSocket: WebOSTVSocket {
    var onOpen: (() -> Void)?
    var onText: ((String) -> Void)?
    var onFailure: (() -> Void)?
    var onCertificate: ((String) -> Void)?
    var url: URL?
    var pin: String?
    var closeCount = 0
    var sent: [String] = []
    var completions: [(Bool) -> Void] = []
    var pings: [(Bool) -> Void] = []
    func open(_ url: URL, fingerprint: String?) { self.url = url; pin = fingerprint }
    func send(_ text: String, completion: @escaping (Bool) -> Void) {
        sent.append(text); completions.append(completion)
    }
    func ping(completion: @escaping (Bool) -> Void) { pings.append(completion) }
    // Retain callbacks deliberately, to exercise completions arriving after close.
    func close() { closeCount += 1 }
    func complete(_ ok: Bool = true) {
        precondition(!completions.isEmpty, "Fixture expected an outstanding send")
        completions.removeFirst()(ok)
    }
    func reply(type: String, id: String, payload: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: ["type": type, "id": id, "payload": payload])
        onText?(String(data: data, encoding: .utf8)!)
    }
    func requestID(_ index: Int) -> String {
        let object = try! JSONSerialization.jsonObject(with: Data(sent[index].utf8)) as! [String: Any]
        return object["id"] as! String
    }
    func payload(_ index: Int) -> [String: Any] {
        let object = try! JSONSerialization.jsonObject(with: Data(sent[index].utf8)) as! [String: Any]
        return object["payload"] as! [String: Any]
    }
}

@MainActor
private final class TVRig {
    static let pin = String(repeating: "a", count: 64)
    static let host = "192.168.1.20"
    static let key = "fixture-approved-client-key"
    let store: TVMemoryStore
    var sockets: [TVFakeSocket] = []
    lazy var controller = WebOSTVController(storage: store, makeSocket: { [unowned self] in
        let socket = TVFakeSocket(); sockets.append(socket); return socket
    })
    init(saved: WebOSTVPairing? = nil) { store = TVMemoryStore(saved) }
    @discardableResult
    func approveToPointer() -> (control: TVFakeSocket, pointer: TVFakeSocket) {
        controller.connect(host: Self.host)
        if controller.phase == .inspecting {
            sockets.last!.onCertificate?(Self.pin)
            controller.trustAndPair()
        }
        let control = sockets.last!
        control.onOpen?()
        control.complete()
        control.reply(type: "registered", id: control.requestID(0), payload: ["client-key": Self.key])
        control.complete()
        control.reply(type: "response", id: control.requestID(1), payload: [
            "returnValue": true, "socketPath": "ws://\(Self.host):3000/resources/fixture/netinput.pointer.sock"
        ])
        return (control, sockets.last!)
    }
    @discardableResult
    func ready() -> (control: TVFakeSocket, pointer: TVFakeSocket) {
        let channels = approveToPointer()
        channels.pointer.onOpen?()
        return channels
    }
}

@main
struct WebOSTVControllerTests {
    @MainActor static func main() async {
        var passed = 0
        func check(_ condition: Bool, _ title: String) {
            precondition(condition, title); passed += 1
        }

        let demoPairing = WebOSTVPairing(host: TVRig.host, fingerprint: TVRig.pin, clientKey: TVRig.key)
        let demoStore = TVMemoryStore(demoPairing)
        var demoSocketCount = 0
        let disabled = WebOSTVController(enabled: false, storage: demoStore, makeSocket: {
            demoSocketCount += 1; return TVFakeSocket()
        })
        check(demoStore.reads == 0 && disabled.saved == nil,
              "Disabled demo controller does not read or expose saved credentials")
        disabled.connect(host: TVRig.host); disabled.trustAndPair()
        disabled.move(dx: 1, dy: 2); disabled.click(); disabled.scroll(dy: 10); disabled.button(.home)
        disabled.pauseInput(); disabled.resumeInput(); disabled.forget(); disabled.disconnect()
        check(demoSocketCount == 0 && disabled.phase == .idle && !disabled.canControl,
              "Disabled demo controller cannot create sockets or become controllable")
        check(demoStore.reads == 0 && demoStore.writes.isEmpty && demoStore.deletes == 0 && demoStore.value == demoPairing,
              "Demo connection, input and forget operations leave real pairing storage untouched")

        let trust = TVRig()
        check(trust.sockets.isEmpty && trust.controller.phase == .idle, "Initialization never connects")
        trust.controller.trustAndPair()
        check(trust.sockets.isEmpty, "Trust without an inspected certificate does nothing")
        trust.controller.connect(host: "  \(TVRig.host)\n")
        let probe = trust.sockets[0]
        check(trust.controller.phase == .inspecting && !trust.controller.canControl, "Certificate inspection is not authorization")
        check(probe.url?.absoluteString == "wss://192.168.1.20:3001" && probe.pin == nil, "Inspection targets only the selected LAN TLS endpoint")
        probe.onOpen?()
        trust.controller.move(dx: 10, dy: 20); trust.controller.click(); trust.controller.button(.home)
        check(probe.sent.isEmpty && trust.store.writes.isEmpty, "No registration, credentials or actions before explicit trust")
        probe.onCertificate?(TVRig.pin)
        check(trust.controller.phase == .trust && probe.closeCount == 1 && trust.sockets.count == 1, "Inspection closes before awaiting explicit trust")
        check(trust.controller.certificate == TVRig.pin && !trust.controller.canControl, "Inspected certificate alone cannot control TV")
        trust.controller.trustAndPair()
        let control = trust.sockets[1]
        check(control.pin == TVRig.pin && control.sent.isEmpty, "Approved pin is applied before sending registration")
        probe.onFailure?()
        check(trust.controller.phase == .connecting, "A closed inspection probe cannot fail its replacement")
        control.onOpen?()
        check(trust.controller.phase == .approving && control.sent.count == 1, "Control socket open requests TV approval")
        check(control.payload(0)["client-key"] == nil, "Fresh pairing does not invent a credential")
        control.complete()
        let registrationID = control.requestID(0)
        control.reply(type: "response", id: registrationID, payload: ["pairingType": "PROMPT"])
        check(trust.controller.phase == .approving && !trust.controller.canControl && trust.store.writes.isEmpty, "PROMPT is not paired or ready")
        control.reply(type: "registered", id: registrationID, payload: ["client-key": TVRig.key])
        check(trust.controller.phase == .openingPointer && control.sent.count == 2, "Matching registration requests the pointer channel")
        check(trust.store.writes.isEmpty && trust.controller.saved == nil, "Registration alone does not persist a usable pairing")
        control.complete()
        control.reply(type: "response", id: control.requestID(1), payload: [
            "returnValue": true, "socketPath": "ws://192.168.1.20:3000/resources/fixture/netinput.pointer.sock"
        ])
        let pointer = trust.sockets[2]
        check(pointer.url?.absoluteString == "wss://192.168.1.20:3001/resources/fixture/netinput.pointer.sock", "Advertised legacy pointer endpoint is upgraded to TLS")
        check(pointer.pin == control.pin && pointer.pin == TVRig.pin, "Both channels share the explicitly approved pin")
        check(!trust.controller.canControl && trust.store.writes.isEmpty, "Pointer construction is not a successful handshake")
        pointer.onOpen?()
        let pairing = WebOSTVPairing(host: TVRig.host, fingerprint: TVRig.pin, clientKey: TVRig.key)
        check(trust.controller.canControl && trust.controller.phase == .ready, "Pointer open completes readiness")
        check(trust.store.writes == [pairing] && trust.controller.saved == pairing, "Only the ready handshake persists the exact host, pin and client key")
        pointer.onOpen?()
        check(trust.store.writes.count == 1, "Duplicate open cannot persist or repeat setup")
        pointer.onText?("untrusted text that is not an action receipt")
        check(trust.controller.phase == .ready, "Pointer messages are not interpreted as action acknowledgements")

        trust.controller.move(dx: 10, dy: 20)
        trust.controller.move(dx: 3, dy: 4)
        trust.controller.move(dx: 5, dy: 6)
        trust.controller.click()
        trust.controller.move(dx: -2, dy: 0)
        check(pointer.sent == ["type:move\ndx:10.0\ndy:20.0\ndown:0\n\n"], "Only one pointer operation may be in flight")
        pointer.complete()
        check(pointer.sent.last == "type:move\ndx:8.0\ndy:10.0\ndown:0\n\n", "Adjacent pending moves coalesce before the next click")
        pointer.complete()
        check(pointer.sent.last == "type:click\n\n", "Click follows completion of prior motion")
        pointer.complete()
        check(pointer.sent.last == "type:move\ndx:-2.0\ndy:0\ndown:0\n\n", "Movement after click stays after click")
        pointer.complete()
        let beforeInvalid = pointer.sent.count
        trust.controller.move(dx: .nan, dy: 0); trust.controller.move(dx: 501, dy: 0)
        trust.controller.scroll(dy: .infinity)
        check(pointer.sent.count == beforeInvalid, "Invalid pointer values never reach the socket")
        trust.controller.scroll(dy: 9)
        check(pointer.sent.last == "type:scroll\ndx:0\ndy:9.0\n\n", "Scrolling uses the pointer channel")
        pointer.complete()
        trust.controller.button(.back)
        check(pointer.sent.last == "type:button\nname:BACK\n\n", "Allowlisted navigation button uses the same ordered channel")
        pointer.complete()

        trust.controller.move(dx: 1, dy: 2)
        trust.controller.click()
        let beforePause = pointer.sent.count
        var publishedChanges = 0
        let stateObservation = trust.controller.objectWillChange.sink { publishedChanges += 1 }
        trust.controller.pauseInput()
        check(!trust.controller.canControl, "Paused input cannot control TV")
        check(publishedChanges > 0, "Pausing publishes a UI update for computed canControl")
        trust.controller.button(.home); trust.controller.click()
        pointer.complete()
        check(pointer.sent.count == beforePause, "Pause drops queued click and actions attempted while paused")
        let changesBeforeResume = publishedChanges
        trust.controller.resumeInput()
        check(pointer.sent.count == beforePause && trust.controller.canControl, "Resume never replays the discarded queue")
        check(publishedChanges > changesBeforeResume, "Resuming publishes a UI update so the touch surface can re-enable")
        stateObservation.cancel()
        trust.controller.click()
        check(pointer.sent.count == beforePause + 1, "A fresh action after resume is allowed")
        pointer.complete()

        trust.controller.move(dx: 1, dy: 0)
        trust.controller.click()
        let beforeFailure = pointer.sent.count
        pointer.complete(false)
        check(trust.controller.phase == .failed && !trust.controller.canControl, "An uncertain pointer send stops the session")
        check(pointer.closeCount == 1 && control.closeCount == 1, "Failure closes both channels")
        pointer.onOpen?(); control.onFailure?(); pointer.onText?("late response")
        check(trust.controller.phase == .failed && pointer.sent.count == beforeFailure, "Failed-session callbacks cannot revive input or repeat a command")
        let reconnected = trust.ready()
        check(reconnected.control.payload(0)["client-key"] as? String == TVRig.key, "Explicit reconnect reuses only the saved approved key")
        check(reconnected.control.pin == TVRig.pin && reconnected.pointer.pin == TVRig.pin, "Reconnect preserves the saved pin on both channels")
        check(reconnected.pointer.sent.isEmpty, "Reconnect does not replay failed motion or queued clicks")
        trust.controller.disconnect()

        let replaced = TVRig()
        let old = replaced.ready()
        replaced.controller.move(dx: 8, dy: 9)
        replaced.controller.click()
        replaced.controller.connect(host: "10.0.0.7")
        let nextProbe = replaced.sockets.last!
        old.pointer.complete(false); old.pointer.onOpen?(); old.control.onFailure?()
        old.control.reply(type: "registered", id: old.control.requestID(0), payload: ["client-key": "late-key"])
        check(replaced.controller.phase == .inspecting && replaced.controller.host == "10.0.0.7", "Replaced session callbacks cannot alter the new target")
        check(nextProbe.sent.isEmpty && replaced.store.writes.count == 1, "Changing TV requires fresh trust and never leaks the prior key")
        replaced.controller.disconnect()
        nextProbe.onCertificate?(String(repeating: "b", count: 64))
        check(replaced.controller.phase == .idle && replaced.controller.certificate == nil, "Cancelled inspection cannot show late trust UI")

        let wrongID = TVRig()
        wrongID.controller.connect(host: TVRig.host)
        wrongID.sockets[0].onCertificate?(TVRig.pin)
        wrongID.controller.trustAndPair()
        let wrongControl = wrongID.sockets[1]
        wrongControl.onOpen?(); wrongControl.complete()
        wrongControl.reply(type: "registered", id: "different-request", payload: ["client-key": TVRig.key])
        check(wrongID.controller.phase == .failed && wrongID.store.writes.isEmpty && wrongID.sockets.count == 2, "Unmatched authorization cannot open a pointer or save credentials")

        let noStorage = TVRig()
        noStorage.store.rejectWrite = true
        let noStorageChannels = noStorage.approveToPointer()
        noStorageChannels.pointer.onOpen?()
        check(noStorage.controller.phase == .failed && !noStorage.controller.canControl && noStorage.store.writes.isEmpty, "A storage failure cannot leave a controllable unsaved session")
        check(noStorageChannels.pointer.closeCount == 1 && noStorageChannels.control.closeCount == 1, "Storage failure closes both channels")

        let pointerFailure = TVRig()
        let failing = pointerFailure.approveToPointer()
        failing.pointer.onFailure?(); failing.pointer.onOpen?()
        check(pointerFailure.controller.phase == .failed && pointerFailure.store.writes.isEmpty, "Failed pointer handshake cannot save pairing even if open arrives late")

        let pinned = TVRig(saved: pairing)
        check(pinned.sockets.isEmpty && pinned.controller.saved == pairing, "Loading a saved pairing never auto-connects")
        pinned.controller.connect(host: TVRig.host)
        check(pinned.sockets.count == 1 && pinned.sockets[0].pin == TVRig.pin && pinned.controller.phase == .connecting, "Saved pairing connects only with the saved pin")
        pinned.sockets[0].onFailure?()
        check(pinned.controller.phase == .failed && pinned.sockets.count == 1, "Pinned TLS failure never falls back to unpinned trust")
        pinned.controller.forget()
        check(pinned.controller.saved == nil && pinned.store.deletes == 1 && pinned.controller.host.isEmpty, "Explicit forget deletes only TV pairing and stops connection")

        let staleQueue = TVRig()
        let staleChannels = staleQueue.ready()
        staleQueue.controller.move(dx: 1, dy: 0)
        staleQueue.controller.click()
        try? await Task.sleep(for: .milliseconds(550))
        staleChannels.pointer.complete()
        check(staleQueue.controller.phase == .failed && !staleQueue.controller.canControl,
              "A delayed motion completion stops a session whose queued click expired")
        check(staleChannels.pointer.sent.count == 1 && staleChannels.pointer.closeCount == 1,
              "An expired queued click is discarded without transmission or replay")

        let overflow = TVRig()
        let overflowChannels = overflow.ready()
        overflow.controller.click()
        for _ in 0..<25 { overflow.controller.click() }
        check(overflow.controller.phase == .failed && overflowChannels.pointer.sent.count == 1, "A stalled TV cannot accumulate an unbounded click backlog")
        overflowChannels.pointer.complete()
        check(overflowChannels.pointer.sent.count == 1, "Backlog failure never replays queued clicks after a late completion")

        for host in ["127.0.0.1", "8.8.8.8", "169.254.1.1", "172.15.1.2", "172.32.1.2", "192.168.01.2", "192.168.1.256", "tv.local", "https://192.168.1.20", "192.168.1.20:3001", "::1", ""] {
            let invalid = TVRig()
            invalid.controller.connect(host: host)
            check(invalid.controller.phase == .failed && invalid.sockets.isEmpty, "Invalid or non-private TV address never creates a socket")
        }
        for host in ["10.0.0.1", "172.16.0.1", "172.31.255.2", "192.168.1.20"] {
            let valid = TVRig()
            valid.controller.connect(host: host)
            check(valid.controller.phase == .inspecting && valid.sockets.count == 1, "Private IPv4 address starts inspection only")
            valid.controller.disconnect()
        }
        print("PASS \(passed) webOS controller checks (injected sockets/storage; no TV, network or Keychain access)")
    }
}
