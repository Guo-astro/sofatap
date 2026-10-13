import Foundation

private struct Fixture: Decodable {
    let controlPort: Int
    let pointerPort: Int
    let redirectPort: Int
    let controlPin: String
    let pointerPin: String
}

private struct Statistics: Decodable {
    let requests: [String: Int]
    let frames: [String: [String]]
}

@MainActor
private final class Probe {
    let socket = WebOSTVNetworkSocket()
    var opens = 0
    var failures = 0
    var certificates: [String] = []
    var texts: [String] = []
    var sends: [Bool] = []
    var pings: [Bool] = []
    init() {
        socket.onOpen = { [weak self] in self?.opens += 1 }
        socket.onFailure = { [weak self] in self?.failures += 1 }
        socket.onCertificate = { [weak self] in self?.certificates.append($0) }
        socket.onText = { [weak self] in self?.texts.append($0) }
    }
    func send(_ text: String) {
        socket.send(text) { [weak self] in self?.sends.append($0) }
    }
    func ping() { socket.ping { [weak self] in self?.pings.append($0) } }
}

@main
@MainActor
private struct WebOSTVTransportTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
    static func pause(_ milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
    static func wait(_ label: String, until condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            await pause(20)
        }
        require(false, "timeout: \(label)")
    }
    static func url(_ port: Int, _ path: String) -> URL {
        URL(string: "wss://127.0.0.1:\(port)\(path)")!
    }
    static func stats(_ directory: URL) -> Statistics {
        try! JSONDecoder().decode(Statistics.self,
                                 from: Data(contentsOf: directory.appendingPathComponent("stats.json")))
    }
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fixture = try JSONDecoder().decode(Fixture.self,
            from: Data(contentsOf: directory.appendingPathComponent("fixture.json")))
        require(fixture.controlPin != fixture.pointerPin, "fixture requires different leaf certificates")

        let inspect = Probe()
        inspect.socket.open(url(fixture.controlPort, "/inspect"), fingerprint: nil)
        inspect.send("synthetic-client-key-must-not-leave-before-trust")
        await wait("certificate inspection") { !inspect.certificates.isEmpty || inspect.failures > 0 }
        require(inspect.certificates == [fixture.controlPin], "inspection reports exact DER SHA256 once")
        require(inspect.opens == 0, "inspection never opens a WebSocket")
        require(stats(directory).requests["/inspect", default: 0] == 0,
                "inspection must reject TLS before any HTTP/SSAP request")
        require(stats(directory).frames["/inspect", default: []].isEmpty, "inspection sends no credential")
        inspect.socket.close()
        print("PASS inspection: exact fingerprint, no HTTP or credential before trust")

        for (port, pin, path) in [(fixture.controlPort, fixture.controlPin, "/control"),
                                  (fixture.pointerPort, fixture.pointerPin, "/pointer")] {
            let probe = Probe()
            probe.socket.open(url(port, path), fingerprint: pin)
            await wait("pinned open \(path)") { probe.opens > 0 || probe.failures > 0 }
            require(probe.opens == 1 && probe.failures == 0, "correct pin opens \(path)")
            let frame = path == "/pointer" ? "type:move\ndx:2\ndy:-3\ndown:0\n\n" :
                "{\"id\":\"test\",\"type\":\"register\",\"payload\":{\"client-key\":\"synthetic-test-only\"}}"
            probe.send(frame)
            probe.ping()
            await wait("frame and ping \(path)") { !probe.texts.isEmpty && !probe.pings.isEmpty && !probe.sends.isEmpty }
            require(probe.texts == [frame], "real WebSocket round-trip preserves exact frame")
            require(probe.sends == [true] && probe.pings == [true], "send and ping succeed")
            require(stats(directory).frames[path] == [frame], "server receives the exact payload")
            probe.socket.close()
        }
        print("PASS distinct pinned control/pointer TLS connections, text framing and ping")

        for (port, wrongPin, path) in [(fixture.controlPort, fixture.pointerPin, "/wrong-control"),
                                       (fixture.pointerPort, fixture.controlPin, "/wrong-pointer")] {
            let probe = Probe()
            probe.socket.open(url(port, path), fingerprint: wrongPin)
            probe.send("synthetic-input-must-not-leave-with-wrong-pin")
            await wait("wrong pin \(path)") { probe.failures > 0 }
            require(probe.opens == 0 && probe.certificates.isEmpty, "wrong pin is failure, never a fresh trust prompt")
            require(stats(directory).requests[path, default: 0] == 0, "wrong pin rejects before HTTP")
            require(stats(directory).frames[path, default: []].isEmpty, "wrong pin sends no input")
            probe.socket.close()
        }
        print("PASS wrong control and pointer pins reject before HTTP or input")

        let redirected = Probe()
        redirected.socket.open(url(fixture.controlPort, "/redirect"), fingerprint: fixture.controlPin)
        await wait("redirect rejection") { redirected.failures > 0 || redirected.opens > 0 }
        require(redirected.opens == 0, "redirect cannot open WebSocket")
        require(stats(directory).requests["/redirect", default: 0] == 1, "redirect response was actually exercised")
        require(stats(directory).requests["/redirect-target", default: 0] == 0, "cross-port redirect target never receives HTTP")
        redirected.socket.close()
        print("PASS cross-port HTTP redirect rejected")

        for path in ["/binary", "/oversized", "/server-close"] {
            let invalid = Probe()
            invalid.socket.open(url(fixture.controlPort, path), fingerprint: fixture.controlPin)
            await wait("invalid server response \(path)") { invalid.failures > 0 }
            await pause(100)
            require(invalid.failures == 1, "receive/delegate failures are reported only once")
            require(invalid.texts.isEmpty, "\(path) payload never reaches text consumer; received lengths \(invalid.texts.map { $0.utf8.count })")
            invalid.socket.close()
        }
        print("PASS binary/oversized payloads and server close fail once without delivering text")

        let late = Probe()
        late.socket.open(url(fixture.controlPort, "/late"), fingerprint: fixture.controlPin)
        await wait("late-callback setup") { late.opens > 0 }
        late.send("late-response")
        late.ping()
        // No MainActor suspension between queueing these operations and close:
        // completions already queued on MainActor must see the invalidated epoch.
        late.socket.close()
        await pause(400)
        require(late.sends.isEmpty && late.pings.isEmpty && late.texts.isEmpty && late.failures == 0,
                "closed epoch suppresses send/ping/receive/failure callbacks")
        late.socket.open(url(fixture.controlPort, "/reopened"), fingerprint: fixture.controlPin)
        await wait("reopen after close") { late.opens == 2 }
        late.send("new-session")
        await wait("new session echo") { late.texts == ["new-session"] }
        require(late.sends == [true] && late.failures == 0, "new epoch still delivers current callbacks")
        late.socket.close()

        let cancelled = Probe()
        cancelled.socket.open(url(fixture.controlPort, "/cancelled"), fingerprint: fixture.controlPin)
        cancelled.socket.close()
        await pause(300)
        require(cancelled.opens == 0 && cancelled.failures == 0 && cancelled.certificates.isEmpty,
                "cancelled opening cannot publish callbacks")
        print("PASS close invalidates queued callbacks; reconnect has a fresh epoch")
        print("All real loopback TLS/WebSocket transport checks passed. No TV contacted.")
    }
}
