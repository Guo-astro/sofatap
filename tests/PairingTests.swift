import Foundation

@main
struct PairingTests {
    static func main() throws {
        let token = String(repeating: "a", count: 43)
        let fingerprint = String(repeating: "0a", count: 32)
        let good = "sofatap://pair?host=192.0.2.17&port=53319&token=\(token)&fingerprint=\(fingerprint)"
        var passed = 0
        func check(_ name: String, _ body: () throws -> Bool) throws {
            guard try body() else { throw NSError(domain: "PairingTests", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
            passed += 1
        }
        func rejects(_ value: String) -> Bool { (try? Pairing.parse(value)) == nil }
        try check("valid IPv4") { try Pairing.parse(good).host == "192.0.2.17" }
        try check("endpoint") { try Pairing.parse(good).endpoint?.absoluteString == "wss://192.0.2.17:53319/control" }
        try check("hostname") { try Pairing.parse(good.replacingOccurrences(of: "192.0.2.17", with: "Living-Room.local")).host == "living-room.local" }
        try check("leading/trailing whitespace") { try Pairing.parse(" \n" + good + "\n ") == Pairing.parse(good) }
        let invalid: [(String, String)] = [
            ("wrong scheme", good.replacingOccurrences(of: "sofatap:", with: "https:")),
            ("wrong target", good.replacingOccurrences(of: "//pair?", with: "//other?")),
            ("userinfo", good.replacingOccurrences(of: "//pair?", with: "//user@pair?")),
            ("path", good.replacingOccurrences(of: "//pair?", with: "//pair/path?")),
            ("fragment", good + "#something"),
            ("duplicate field", good + "&host=evil.local"),
            ("unknown field", good + "&extra=yes"),
            ("missing field", good.replacingOccurrences(of: "&port=53319", with: "")),
            ("port 0", good.replacingOccurrences(of: "53319", with: "0")),
            ("port high", good.replacingOccurrences(of: "53319", with: "65536")),
            ("port sign", good.replacingOccurrences(of: "53319", with: "+53319")),
            ("short token", good.replacingOccurrences(of: token, with: "short")),
            ("token header injection", good.replacingOccurrences(of: token, with: token + "%0D%0A")),
            ("short fingerprint", good.replacingOccurrences(of: fingerprint, with: "abcdef")),
            ("bad fingerprint", good.replacingOccurrences(of: fingerprint, with: String(repeating: "z", count: 64))),
            ("host url", good.replacingOccurrences(of: "192.0.2.17", with: "http%3A%2F%2Fevil.local")),
            ("host trailing path", good.replacingOccurrences(of: "192.0.2.17", with: "evil.local%2Fcontrol")),
            ("host empty label", good.replacingOccurrences(of: "192.0.2.17", with: "evil..local")),
            ("host leading hyphen", good.replacingOccurrences(of: "192.0.2.17", with: "-evil.local")),
            ("oversized pairing", good + String(repeating: "x", count: 2048))
        ]
        for (name, value) in invalid { try check(name) { rejects(value) } }
        print("PASS \(passed) native pairing validation checks")
    }
}
