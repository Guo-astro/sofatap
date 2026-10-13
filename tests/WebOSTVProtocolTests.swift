import Foundation

@main
struct WebOSTVProtocolTests {
    static func main() throws {
        var passed = 0
        func check(_ name: String, _ condition: Bool) { precondition(condition, name); passed += 1 }
        func reject(_ name: String, _ expected: WebOSTVProtocolError? = nil, _ operation: () throws -> Void) {
            do { try operation(); preconditionFailure(name) }
            catch let error as WebOSTVProtocolError {
                if let expected { precondition(error == expected, name) }
                passed += 1
            } catch { preconditionFailure("Unexpected error: \(name)") }
        }
        func json(_ value: [String: Any]) throws -> String {
            String(data: try JSONSerialization.data(withJSONObject: value), encoding: .utf8)!
        }
        let endpoint = try WebOSTVEndpoint(host: "192.168.1.70")
        check("secure fixed control endpoint", endpoint.controlURL.absoluteString == "wss://192.168.1.70:3001")
        for host in ["10.0.0.1", "172.16.0.1", "172.31.255.254", "192.168.255.254"] {
            check("accept RFC1918", try WebOSTVEndpoint(host: host).host == host)
        }
        for host in ["", "192.168.1", "192.168.1.256", "192.168.01.1", "192.168.1.1 ",
                     " 192.168.1.1", "192.168.1.1\n", "192.168.1.1:3001", "wss://192.168.1.1", "user@192.168.1.1",
                     "127.0.0.1", "0.0.0.0", "8.8.8.8", "169.254.1.1", "100.64.0.1", "172.15.1.1", "172.32.1.1",
                     "192.167.1.1", "224.0.0.1", "tv.local", "localhost", "::1", "3232235777", "0xc0a80101"] {
            reject("reject unsafe or ambiguous host", .invalidEndpoint) { _ = try WebOSTVEndpoint(host: host) }
        }
        check("explicit local fixture endpoint", try WebOSTVEndpoint(host: "127.0.0.1", allowLoopback: true).host == "127.0.0.1")
        reject("fixture option does not admit public addresses", .invalidEndpoint) {
            _ = try WebOSTVEndpoint(host: "8.8.8.8", allowLoopback: true)
        }

        let registrationText = try WebOSTVProtocol.registration(id: "register-1")
        let registration = try JSONSerialization.jsonObject(with: Data(registrationText.utf8)) as! [String: Any]
        let payload = registration["payload"] as! [String: Any]
        let manifest = payload["manifest"] as! [String: Any]
        check("request is registration", registration["type"] as? String == "register" && registration["id"] as? String == "register-1")
        check("TV prompt required", payload["pairingType"] as? String == "PROMPT")
        check("only minimal unsigned permissions", Set(manifest.keys) == ["manifestVersion", "permissions"] &&
              manifest["manifestVersion"] as? Int == 1 && manifest["permissions"] as? [String] == ["CONTROL_MOUSE_AND_KEYBOARD"])
        check("first registration has no credential", payload["client-key"] == nil && !registrationText.contains("signed"))
        let fixtureKey = "fixture-key-never-a-real-TV-key"
        let savedText = try WebOSTVProtocol.registration(id: "register-2", clientKey: fixtureKey)
        let saved = try JSONSerialization.jsonObject(with: Data(savedText.utf8)) as! [String: Any]
        check("saved key can be supplied", (saved["payload"] as? [String: Any])?["client-key"] as? String == fixtureKey)
        for badID in ["", "bad\nid", "\"bad", String(repeating: "a", count: 65), "非ASCII"] {
            reject("registration ID validation", .invalidIdentifier) { _ = try WebOSTVProtocol.registration(id: badID) }
            reject("request ID validation", .invalidIdentifier) { _ = try WebOSTVProtocol.pointerRequest(id: badID) }
        }
        for key in ["", "bad\nkey", "bad key", String(repeating: "a", count: 257), "秘密"] {
            reject("client key validation", .invalidClientKey) { _ = try WebOSTVProtocol.registration(id: "r", clientKey: key) }
        }
        let request = try JSONSerialization.jsonObject(with: Data(WebOSTVProtocol.pointerRequest(id: "pointer-1").utf8)) as! [String: Any]
        check("fixed pointer service only", request["type"] as? String == "request" && request["id"] as? String == "pointer-1" &&
              request["uri"] as? String == "ssap://com.webos.service.networkinput/getPointerInputSocket")

        let registered = try json(["type": "registered", "id": "register-1", "payload": ["client-key": fixtureKey]])
        check("correlated registration returns key", try WebOSTVProtocol.parse(registered, endpoint: endpoint,
              expecting: .registration(id: "register-1")) == .registered(clientKey: fixtureKey))
        for expectation: WebOSTVExpectedResponse in [.none, .registration(id: "other"), .pointerSocket(id: "register-1")] {
            reject("unsolicited, stale and wrong-kind registration rejected", .unexpectedResponse) {
                _ = try WebOSTVProtocol.parse(registered, endpoint: endpoint, expecting: expectation)
            }
        }
        let registeredWithoutID = try json(["type": "registered", "payload": ["client-key": fixtureKey]])
        check("legacy no-ID registered needs exclusive pending registration", try WebOSTVProtocol.parse(registeredWithoutID,
              endpoint: endpoint, expecting: .registration(id: "register-1")) == .registered(clientKey: fixtureKey))
        for expectation: WebOSTVExpectedResponse in [.none, .pointerSocket(id: "register-1")] {
            reject("no-ID unsolicited registered cannot replace a pairing", .unexpectedResponse) {
                _ = try WebOSTVProtocol.parse(registeredWithoutID, endpoint: endpoint, expecting: expectation)
            }
        }
        let prompt = try json(["type": "response", "id": "register-1", "payload": ["pairingType": "PROMPT"]])
        check("pairing prompt is not authorization", try WebOSTVProtocol.parse(prompt, endpoint: endpoint,
              expecting: .registration(id: "register-1")) == .other)
        check("hello does not authorize", try WebOSTVProtocol.parse("{\"type\":\"hello\",\"payload\":{}}", endpoint: endpoint, expecting: .none) == .other)
        for bad in ["", "[]", "null", "{}", "{\"type\":7}", "{broken", "{}{}", "{\"type\":\"hello\"}junk"] {
            reject("malformed JSON denied", .malformedMessage) { _ = try WebOSTVProtocol.parse(bad, endpoint: endpoint, expecting: .none) }
        }
        reject("message bound before JSON decode", .messageTooLarge) {
            _ = try WebOSTVProtocol.parse(String(repeating: " ", count: WebOSTVProtocol.maximumMessageBytes + 1), endpoint: endpoint, expecting: .none)
        }
        for bad: Any in [NSNull(), 42, true, "wrong"] {
            let message = try json(["type": "registered", "id": bad, "payload": ["client-key": fixtureKey]])
            reject("ID correlation never coerces values", .unexpectedResponse) {
                _ = try WebOSTVProtocol.parse(message, endpoint: endpoint, expecting: .registration(id: "register-1"))
            }
        }
        let missingKey = try json(["type": "registered", "id": "register-1", "payload": [:]])
        reject("registered needs a valid key", .invalidClientKey) {
            _ = try WebOSTVProtocol.parse(missingKey, endpoint: endpoint, expecting: .registration(id: "register-1"))
        }
        for key: Any in ["", "bad\nkey", String(repeating: "a", count: 257), NSNull(), 42] {
            let invalidKey = try json(["type": "registered", "id": "register-1", "payload": ["client-key": key]])
            reject("incoming registration validates key", .invalidClientKey) {
                _ = try WebOSTVProtocol.parse(invalidKey, endpoint: endpoint, expecting: .registration(id: "register-1"))
            }
        }
        let remoteError = try json(["type": "error", "id": "register-1", "error": "401 secret \(fixtureKey)"])
        let rejection = try WebOSTVProtocol.parse(remoteError, endpoint: endpoint, expecting: .registration(id: "register-1"))
        check("server error is sanitized", rejection == .error(code: 401) && !String(describing: rejection).contains(fixtureKey))
        for expectation: WebOSTVExpectedResponse in [.none, .registration(id: "stale")] {
            reject("uncorrelated errors cannot end current request", .unexpectedResponse) {
                _ = try WebOSTVProtocol.parse(remoteError, endpoint: endpoint, expecting: expectation)
            }
        }
        check("response debug text redacts key", !String(describing: WebOSTVResponse.registered(clientKey: fixtureKey)).contains(fixtureKey))

        let path = "/resources/fixture_resource-1/netinput.pointer.sock"
        let secure = "wss://192.168.1.70:3001\(path)"
        let legacy = "ws://192.168.1.70:3000\(path)"
        for raw in [secure, legacy] {
            check("pointer endpoint always secure", try endpoint.pointerURL(raw).absoluteString == secure)
            let message = try json(["type": "response", "id": "pointer-1", "payload": ["socketPath": raw, "returnValue": true]])
            check("correlated pointer response", try WebOSTVProtocol.parse(message, endpoint: endpoint,
                  expecting: .pointerSocket(id: "pointer-1")) == .pointerSocket(URL(string: secure)!))
            reject("pointer response does not finish registration", .unexpectedResponse) {
                _ = try WebOSTVProtocol.parse(message, endpoint: endpoint, expecting: .registration(id: "pointer-1"))
            }
        }
        check("known root pointer path", try endpoint.pointerURL("wss://192.168.1.70:3001/netinput.pointer.sock").path == "/netinput.pointer.sock")
        let pointerWithoutReturnValue = try json(["type": "response", "id": "pointer-1", "payload": ["socketPath": secure]])
        check("legacy pointer reply may omit returnValue", try WebOSTVProtocol.parse(pointerWithoutReturnValue,
              endpoint: endpoint, expecting: .pointerSocket(id: "pointer-1")) == .pointerSocket(URL(string: secure)!))
        for expectation: WebOSTVExpectedResponse in [.none, .pointerSocket(id: "stale")] {
            reject("uncorrelated pointer replies never open a socket", .unexpectedResponse) {
                _ = try WebOSTVProtocol.parse(pointerWithoutReturnValue, endpoint: endpoint, expecting: expectation)
            }
        }
        let pointerWithoutID = try json(["type": "response", "payload": ["socketPath": secure, "returnValue": true]])
        reject("pointer reply always needs correlated ID", .unexpectedResponse) {
            _ = try WebOSTVProtocol.parse(pointerWithoutID, endpoint: endpoint, expecting: .pointerSocket(id: "pointer-1"))
        }
        for raw in ["wss://192.168.1.71:3001\(path)", "wss://8.8.8.8:3001\(path)", "wss://tv.local:3001\(path)",
                    "ws://192.168.1.70:3001\(path)", "wss://192.168.1.70:3000\(path)", "https://192.168.1.70:3001\(path)",
                    "wss://192.168.1.70\(path)", "wss://user:pass@192.168.1.70:3001\(path)", secure + "?key=secret", secure + "#fragment",
                    "wss://192.168.1.70:3001/redirect", "wss://192.168.1.70:3001/resources/../netinput.pointer.sock",
                    "wss://192.168.1.70:3001/resources/%2e%2e/netinput.pointer.sock", "wss://192.168.1.70:3001/resources/a%2fb/netinput.pointer.sock",
                    "wss://192.168.1.70:3001/resources/a/b/netinput.pointer.sock", "wss://192.168.1.70:3001//netinput.pointer.sock",
                    "wss://192.168.1.70:3001/resources//netinput.pointer.sock", "wss://192.168.1.70:3001/resources/" + String(repeating: "a", count: 129) + "/netinput.pointer.sock",
                    secure + "\n", secure + " ", "//192.168.1.70:3001\(path)", "wss://192.168.001.70:3001\(path)"] {
            reject("untrusted pointer endpoint denied", .invalidPointerEndpoint) { _ = try endpoint.pointerURL(raw) }
        }
        for value: Any in [false, 1, "true", NSNull()] {
            let message = try json(["type": "response", "id": "pointer-1", "payload": ["socketPath": secure, "returnValue": value]])
            reject("pointer success must be boolean true", .malformedMessage) {
                _ = try WebOSTVProtocol.parse(message, endpoint: endpoint, expecting: .pointerSocket(id: "pointer-1"))
            }
        }
        let pointerDescription = String(describing: WebOSTVResponse.pointerSocket(URL(string: secure)!))
        check("pointer resource omitted from debug text", !pointerDescription.contains("fixture_resource"))

        check("click framing", try WebOSTVProtocol.encode(.click) == "type:click\n\n")
        check("move framing and no drag", try WebOSTVProtocol.encode(.move(dx: 12.5, dy: -4)) == "type:move\ndx:12.5\ndy:-4.0\ndown:0\n\n")
        check("scroll framing", try WebOSTVProtocol.encode(.scroll(dx: 0, dy: -120)) == "type:scroll\ndx:0\ndy:-120.0\n\n")
        check("negative zero normalized", try WebOSTVProtocol.encode(.move(dx: -0.0, dy: 0)) == "type:move\ndx:0\ndy:0\ndown:0\n\n")
        check("inclusive motion bounds", try WebOSTVProtocol.encode(.move(dx: 500, dy: -500)).contains("dx:500.0"))
        check("inclusive scroll bounds", try WebOSTVProtocol.encode(.scroll(dx: 1200, dy: -1200)).contains("dy:-1200.0"))
        for button in WebOSTVButton.allCases {
            check("typed button whitelist", try WebOSTVProtocol.encode(.button(button)) == "type:button\nname:\(button.rawValue)\n\n")
        }
        check("arbitrary button rejected by type", WebOSTVButton(rawValue: "HOME\ntype:click") == nil && WebOSTVButton(rawValue: "POWER") == nil)
        for motion in [Double.nan, .infinity, -.infinity, 500.01, -500.01] {
            reject("invalid x motion", .invalidMotion) { _ = try WebOSTVProtocol.encode(.move(dx: motion, dy: 0)) }
            reject("invalid y motion", .invalidMotion) { _ = try WebOSTVProtocol.encode(.move(dx: 0, dy: motion)) }
        }
        for motion in [Double.nan, .infinity, -.infinity, 1200.01, -1200.01] {
            reject("invalid scroll", .invalidMotion) { _ = try WebOSTVProtocol.encode(.scroll(dx: 0, dy: motion)) }
        }
        print("PASS \(passed) webOS protocol checks (pure fixtures; no TV connection or device input)")
    }
}
