import Foundation

/// A real URLSession/PinnedSessionDelegate peer for the production Java receiver.
/// Fixture storage and the receiver Input driver are in memory. There is no UI or OS input.
private struct InteropFixture: Decodable { let qr: String }
private struct InteropStats: Decodable {
    struct Action: Decodable { let type: String; let dx: Double?; let dy: Double?; let key: String? }
    let paired: Bool
    let actions: [Action]
    let snapshots: Int
    let disconnects: Int
    let connected: Bool
}
private final class InteropMemoryStore: AndroidTVPairingStorage {
    var value: AndroidTVPairing?
    var writes = 0
    func read() -> AndroidTVPairing? { value }
    func write(_ pairing: AndroidTVPairing) throws { value = pairing; writes += 1 }
    func delete() throws { value = nil }
}
@MainActor private final class SocketProbe {
    let socket = AndroidTVNetworkSocket()
    var failures = 0
    var texts = 0
    init() {
        socket.onFailure = { [weak self] in self?.failures += 1 }
        socket.onText = { [weak self] _ in self?.texts += 1 }
    }
}
@main @MainActor private struct AndroidTVInteropTests {
    static func require(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fputs("FAIL: \(label)\n", stderr); exit(1) }
    }
    static func pause(_ milliseconds: UInt64) async { try? await Task.sleep(nanoseconds: milliseconds * 1_000_000) }
    static func wait(_ label: String, until condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            await pause(20)
        }
        require(false, "timeout: \(label)")
    }
    static func stats(_ dir: URL) -> InteropStats? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("stats.json")) else { return nil }
        return try? JSONDecoder().decode(InteropStats.self, from: data)
    }
    static func main() async throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fixture = try JSONDecoder().decode(InteropFixture.self, from: Data(contentsOf: dir.appendingPathComponent("fixture.json")))
        let pairing = try AndroidTVPairing.parse(fixture.qr)
        let wrongPin = SocketProbe()
        wrongPin.socket.open(AndroidTVPairing(host: pairing.host, port: pairing.port,
            token: pairing.token, fingerprint: String(repeating: pairing.fingerprint.first == "a" ? "b" : "a", count: 64)))
        await wait("wrong certificate rejected") { wrongPin.failures > 0 }
        require(wrongPin.texts == 0, "incorrect pin never reaches hello")
        require(stats(dir)?.paired == false && stats(dir)?.actions.isEmpty == true, "pin rejection does not consume QR or perform input")
        wrongPin.socket.close()
        print("PASS Swift certificate pin rejects before Java pairing authorization")

        let wrongToken = SocketProbe()
        wrongToken.socket.open(pairing.replacingToken(String(repeating: "x", count: 43)))
        await wait("wrong bearer rejected") { wrongToken.failures > 0 }
        wrongToken.socket.close()
        await wait("controller slot released") { stats(dir)?.connected == false }
        require(wrongToken.texts == 0 && stats(dir)?.paired == false, "wrong bearer does not consume QR")
        print("PASS Java rejects an unauthorized Swift WebSocket upgrade")

        let store = InteropMemoryStore()
        let controller = AndroidTVController(storage: store)
        controller.pair(fixture.qr)
        await wait("native controller hello") { controller.phase == .ready || controller.phase == .failed }
        if controller.phase == .failed { fputs("Native controller diagnostic: \(controller.notice)\n", stderr) }
        require(controller.canControl && store.writes == 1, "real Java hello enables native controller and persists once")
        require(store.value?.token != pairing.token && store.value?.fingerprint == pairing.fingerprint, "bootstrap replaced over pinned TLS")
        print("PASS real Swift controller/Java hello and one-time credential rotation")

        controller.move(dx: 12, dy: -3)
        controller.click()
        controller.scroll(dy: -9)
        controller.key(.back)
        controller.key(.home)
        await wait("five acknowledged native input actions") { (stats(dir)?.actions.count ?? 0) >= 5 || controller.phase == .failed }
        let sent = stats(dir)!.actions
        require(controller.canControl && sent.map(\.type) == ["move", "click", "scroll", "key", "key"], "native queue and Java ACKs preserve action order")
        require(sent[0].dx == 12 && sent[0].dy == -3 && sent[2].dy == -9 && sent[3].key == "back" && sent[4].key == "home", "wire deltas and buttons match receiver actions")
        controller.pauseInput(); controller.click(); await pause(200)
        require(stats(dir)?.actions.count == 5, "paused native input is not sent")
        controller.resumeInput()
        print("PASS native move/click/scroll/Back/Home and serial Java acknowledgments")

        try Data().write(to: dir.appendingPathComponent("block-input"))
        await wait("heartbeat detects missing receiver permission") { controller.phase == .ready && !controller.canControl }
        require(controller.status?.inputStatus == .accessibilityRequired, "real ping reports inaccessible receiver")
        controller.click(); await pause(100)
        require(stats(dir)?.actions.count == 5, "revoked receiver permission blocks native input")
        try FileManager.default.removeItem(at: dir.appendingPathComponent("block-input"))
        await wait("heartbeat observes receiver permission restored") { controller.canControl }
        await wait("fixture publishes heartbeat snapshots") { (stats(dir)?.snapshots ?? 0) >= 3 }
        require((stats(dir)?.snapshots ?? 0) >= 3, "real Java ping snapshots exercised")
        print("PASS application heartbeat refreshes permissions across real TLS/WebSocket")

        controller.disconnect()
        await wait("first controller disconnect") { stats(dir)?.connected == false }
        let consumedQR = SocketProbe(); consumedQR.socket.open(pairing)
        await wait("consumed QR cannot reconnect") { consumedQR.failures > 0 }
        consumedQR.socket.close()
        await wait("consumed QR rejection releases slot") { stats(dir)?.connected == false }
        require(consumedQR.texts == 0, "bootstrap is one-use")
        controller.reconnect()
        await wait("native persistent credential resumes") { controller.phase == .ready || controller.phase == .failed }
        require(controller.canControl && store.writes == 1 && stats(dir)?.actions.count == 5, "reconnect authenticates without rotation or replay")
        let second = SocketProbe(); second.socket.open(store.value!)
        await wait("second controller rejected") { second.failures > 0 }
        require(second.texts == 0 && controller.canControl, "single-controller rejection preserves active session")
        second.socket.close()
        controller.key(.back)
        await wait("resumed native input") { stats(dir)?.actions.count == 6 || controller.phase == .failed }
        require(stats(dir)?.actions.last?.key == "back" && controller.canControl, "current controller remains usable")
        controller.disconnect()
        await wait("all controllers closed") { stats(dir)?.connected == false }
        print("PASS persistent reconnect, consumed-QR rejection, single-controller admission and no replay")
        print("Swift/Java interop passed with actual native pinned transport; injected receiver input only, no TV, Keychain or desktop input.")
    }
}
