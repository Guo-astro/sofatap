import Foundation
import Combine

private enum StorageFailure: Error { case failed }
private final class MemoryStore: AndroidTVPairingStorage {
    var value: AndroidTVPairing?
    var reads = 0
    var writes = 0
    var deletes = 0
    var refuseWrite = false
    func read() -> AndroidTVPairing? { reads += 1; return value }
    func write(_ pairing: AndroidTVPairing) throws {
        if refuseWrite { throw StorageFailure.failed }
        writes += 1; value = pairing
    }
    func delete() throws { deletes += 1; value = nil }
}
@MainActor private final class Socket: AndroidTVSocket {
    var onText: ((String) -> Void)?
    var onFailure: (() -> Void)?
    var pairing: AndroidTVPairing?
    var sent: [[String: Any]] = []
    var closed = 0
    var completions: [(Bool) -> Void] = []
    func open(_ pairing: AndroidTVPairing) { self.pairing = pairing }
    func send(_ text: String, completion: @escaping (Bool) -> Void) {
        sent.append(try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any])
        completions.append(completion)
    }
    func close() { closed += 1 }
    func reply(_ object: [String: Any]) {
        onText?(String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!)
    }
    func ack(_ index: Int, ok: Bool = true, extra: [String: Any] = [:]) {
        var object: [String: Any] = ["type": "ack", "id": sent[index]["id"]!, "ok": ok]
        extra.forEach { object[$0.key] = $0.value }
        reply(object)
    }
}
@MainActor private final class Rig {
    let store = MemoryStore()
    var sockets: [Socket] = []
    lazy var controller = AndroidTVController(storage: store, makeSocket: { [unowned self] in
        let socket = Socket(); sockets.append(socket); return socket
    })
    func pair() -> Socket { controller.pair(Self.link); return sockets.last! }
    func ready() -> Socket { let socket = pair(); socket.reply(Self.hello()); return socket }
    nonisolated static let token = String(repeating: "a", count: 43)
    nonisolated static let replacement = String(repeating: "b", count: 43)
    nonisolated static let pin = String(repeating: "a", count: 64)
    nonisolated static let link = "sofatap://tv?host=192.168.1.2&port=53319&token=\(token)&fingerprint=\(pin)"
    static func status(_ available: Bool = true) -> [String: Any] {
        ["inputAvailable": available, "inputStatus": available ? "ready" : "accessibility_required",
         "capabilities": ["overlayCursor": true, "nodeClick": true, "scroll": true, "back": true,
                          "home": true, "directionalFocus": true, "text": false, "rawMouse": false,
                          "rightClick": false, "drag": false]]
    }
    static func hello(token: String? = replacement, available: Bool = true) -> [String: Any] {
        var object = status(available)
        object["type"] = "hello"; object["version"] = 1; object["platform"] = "androidtv"; object["name"] = "Fixture TV"
        if let token { object["pairingToken"] = token }
        return object
    }
}
@main struct AndroidTVControllerTests {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ title: String, _ condition: Bool) { precondition(condition, title); count += 1 }
        func rejected(_ title: String, _ operation: () throws -> Void) {
            do { try operation(); preconditionFailure(title) } catch { count += 1 }
        }
        func encoded(_ value: [String: Any]) -> String { String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)! }
        let pairing = try AndroidTVPairing.parse(Rig.link)
        check("TV uses pinned secure endpoint", pairing.endpoint.absoluteString == "wss://192.168.1.2:53319/control")
        check("TV QR does not replace PC", (try? Pairing.parse(Rig.link)) == nil)
        for host in ["127.0.0.1", "8.8.8.8", "169.254.1.1", "tv.local", "192.168.01.2", "192.168.1.256", "172.32.0.1", "10.1.2", "::1"] {
            rejected("reject non-private or noncanonical endpoint") { _ = try AndroidTVPairing.parse(Rig.link.replacingOccurrences(of: "192.168.1.2", with: host)) }
        }
        for bad in [Rig.link + "&host=10.0.0.1", Rig.link + "&extra=1", Rig.link + "#fragment", Rig.link.replacingOccurrences(of: "//tv?", with: "//pair?"), Rig.link.replacingOccurrences(of: "53319", with: "65536"), Rig.link.replacingOccurrences(of: Rig.token, with: "short")] {
            rejected("malformed QR fails closed") { _ = try AndroidTVPairing.parse(bad) }
        }
        for mutation: (String, Any) in [("version", true), ("version", 1.5), ("version", 2), ("platform", "windows"), ("name", "bad\nname"), ("inputAvailable", 1), ("inputStatus", "unknown"), ("pairingToken", "short")] {
            var hello = Rig.hello(); hello[mutation.0] = mutation.1
            rejected("invalid hello fails closed") { _ = try AndroidTVProtocol.parse(encoded(hello)) }
        }
        var wrongCaps = Rig.hello(); var caps = wrongCaps["capabilities"] as! [String: Any]; caps["rawMouse"] = true; wrongCaps["capabilities"] = caps
        rejected("unexpected raw mouse capability not assumed compatible") { _ = try AndroidTVProtocol.parse(encoded(wrongCaps)) }
        rejected("binary-like JSON disallowed") { _ = try AndroidTVProtocol.parse("[]") }
        rejected("oversize response disallowed") { _ = try AndroidTVProtocol.parse(String(repeating: "x", count: 16385)) }
        rejected("nonfinite movement disallowed") { _ = try AndroidTVProtocol.encode(.move(dx: .nan, dy: 1), id: UUID().uuidString) }
        rejected("unbounded movement disallowed") { _ = try AndroidTVProtocol.encode(.scroll(dx: 0, dy: 501), id: UUID().uuidString) }
        check("click carries no raw button", try AndroidTVProtocol.encode(.click, id: UUID().uuidString).contains("click"))
        do {
            let rig = Rig(), socket = rig.pair()
            check("QR bootstrap never persisted", rig.store.writes == 0 && rig.controller.saved == nil)
            check("connecting cannot control", !rig.controller.canControl)
            socket.reply(Rig.hello())
            check("valid hello rotates secret", rig.controller.saved?.token == Rig.replacement && rig.store.value?.token != Rig.token && rig.store.writes == 1)
            check("ready only after hello", rig.controller.canControl)
            rig.controller.move(dx: 4, dy: 2); rig.controller.click(); rig.controller.move(dx: 3, dy: 1)
            check("one ACK outstanding", socket.sent.count == 1)
            socket.ack(0)
            check("movement precedes click", socket.sent[1]["type"] as? String == "click")
            socket.ack(1)
            check("movement after click retained", socket.sent[2]["type"] as? String == "move")
            rig.controller.pauseInput(); rig.controller.click(); socket.ack(2)
            check("paused input cleared", socket.sent.count == 3)
            rig.controller.resumeInput(); rig.controller.key(.back)
            check("explicit back key", socket.sent[3]["key"] as? String == "back")
            rig.controller.click(); socket.ack(3, ok: false)
            check("rejected action discards queue", socket.sent.count == 4)
            rig.controller.disconnect(); rig.controller.reconnect()
            let resumed = rig.sockets.last!
            check("manual resume uses returned credential", resumed.pairing?.token == Rig.replacement)
            resumed.reply(Rig.hello(token: nil))
            check("resume accepts no replacement", rig.controller.canControl && rig.store.writes == 1)
            socket.onFailure?(); socket.reply(Rig.hello())
            check("old callbacks isolated", rig.controller.canControl && rig.store.writes == 1)
            check("no replay after reconnect", resumed.sent.isEmpty)
            rig.controller.forget()
            check("forget removes credential", rig.store.deletes == 1 && rig.controller.saved == nil)
        }
        do {
            let rig = Rig(), socket = rig.pair()
            socket.reply(Rig.hello(token: nil))
            check("bootstrap requires replacement", rig.controller.phase == .failed && rig.store.writes == 0)
        }
        do {
            let rig = Rig(); rig.store.refuseWrite = true
            let socket = rig.pair(); socket.reply(Rig.hello())
            check("failed secure save never enables control", rig.controller.phase == .failed && !rig.controller.canControl)
        }
        do {
            let rig = Rig(), socket = rig.pair(); socket.reply(Rig.hello(available: false))
            check("paired without permissions remains disabled", rig.controller.phase == .ready && !rig.controller.canControl && rig.store.writes == 1)
            rig.controller.click(); check("no input while permissions missing", socket.sent.isEmpty)
            rig.controller.disconnect()
        }
        do {
            let rig = Rig(), socket = rig.ready()
            rig.controller.click(); socket.ack(0, extra: Rig.status(false))
            check("revoked permission disables immediately", !rig.controller.canControl)
            rig.controller.disconnect()
        }
        do {
            let rig = Rig(), socket = rig.ready()
            rig.controller.click()
            socket.reply(["type": "ack", "id": UUID().uuidString, "ok": true])
            check("wrong ACK cannot acknowledge input", rig.controller.phase == .failed)
        }
        do {
            let rig = Rig(), socket = rig.ready()
            rig.controller.click(); rig.controller.click(); socket.onFailure?()
            check("disconnect clears queued actions", rig.controller.phase == .failed && socket.sent.count == 1)
            rig.controller.reconnect(); let resumed = rig.sockets.last!; resumed.reply(Rig.hello(token: nil))
            check("uncertain clicks never retried", resumed.sent.isEmpty)
            rig.controller.disconnect()
        }
        do {
            let rig = Rig(), socket = rig.ready()
            rig.controller.click()
            for _ in 0..<25 { rig.controller.click() }
            check("bounded action queue fails closed", rig.controller.phase == .failed && socket.sent.count == 1)
        }
        do {
            let rig = Rig(), socket = rig.ready()
            rig.controller.click(); rig.controller.click()
            try await Task.sleep(nanoseconds: 600_000_000)
            socket.ack(0)
            check("stale queued clicks expire rather than replaying late", socket.sent.count == 1)
            rig.controller.disconnect()
        }
        do {
            let timed = Rig(), timedSocket = timed.ready()
            timed.controller.click()
            let heartbeat = Rig(), heartbeatSocket = heartbeat.ready()
            try await Task.sleep(nanoseconds: 3_250_000_000)
            check("unacknowledged action expires without retry", timed.controller.phase == .failed && timedSocket.sent.count == 1)
            check("heartbeat requests fresh capability state", heartbeatSocket.sent.count == 1 && heartbeatSocket.sent[0]["type"] as? String == "ping")
            heartbeatSocket.ack(0, extra: Rig.status(false))
            check("heartbeat detects permission revocation", !heartbeat.controller.canControl)
            heartbeat.controller.disconnect()
        }
        do {
            let store = MemoryStore(); var created = 0
            let demo = AndroidTVController(enabled: false, storage: store, makeSocket: { created += 1; return Socket() })
            demo.pair(Rig.link); demo.reconnect(); demo.forget(); demo.click()
            check("demo has no Keychain or network", created == 0 && store.reads == 0 && store.writes == 0 && store.deletes == 0)
        }
        print("\(count) Android TV iOS protocol/lifecycle checks passed; no device, Keychain or desktop input.")
    }
}
