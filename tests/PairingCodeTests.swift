import Foundation

@main struct PairingCodeTests {
    static func main() throws {
        var count = 0
        func check(_ label: String, _ value: @autoclosure () throws -> Bool) throws {
            guard try value() else { fatalError("FAIL: \(label)") }; count += 1
        }
        func rejects(_ label: String, _ raw: String) throws {
            try check(label, (try? PairingCode.parse(raw)) == nil)
        }
        let token = String(repeating: "a", count: 43), pin = String(repeating: "b", count: 64)
        let desktop = "sofatap://pair?host=192.168.1.7&port=53317&token=\(token)&fingerprint=\(pin)"
        let television = "sofatap://tv?host=192.168.1.8&port=53319&token=\(token)&fingerprint=\(pin)"
        func labeled(_ base: String, platform: String? = nil, name: String? = nil) -> String {
            var components = URLComponents(string: base)!
            if let platform { components.queryItems?.append(URLQueryItem(name: "platform", value: platform)) }
            if let name { components.queryItems?.append(URLQueryItem(name: "name", value: name)) }
            return components.string!
        }
        let legacyPC = try Pairing.parse(desktop), legacyTV = try AndroidTVPairing.parse(television)
        try check("legacy computer routes to desktop", try PairingCode.parse(desktop) == .computer(legacyPC))
        try check("legacy TV routes to Android", try PairingCode.parse(television) == .androidTV(legacyTV))
        try check("legacy metadata stays optional", legacyPC.name == nil && legacyPC.platform == nil && legacyTV.name == nil && legacyTV.platform == nil)
        for platform in ["windows", "macos", "linux"] {
            let parsed = try Pairing.parse(labeled(desktop, platform: platform, name: "  客厅 + Living Room  "))
            try check("\(platform) is routed with normalized metadata", try PairingCode.parse(labeled(desktop, platform: platform, name: "  客厅 + Living Room  ")) == .computer(parsed) && parsed.name == "客厅 + Living Room" && parsed.platform == platform)
            try check("metadata leaves TLS endpoint and identity intact", parsed.endpoint == legacyPC.endpoint && parsed.deviceIdentity == legacyPC.deviceIdentity && parsed.token == token && parsed.fingerprint == pin)
            try parsed.validateForStorage()
        }
        let tv = try AndroidTVPairing.parse(labeled(television, platform: "androidtv", name: "Sony + テレビ"))
        try check("TV metadata routes without a brand choice", try PairingCode.parse(labeled(television, platform: "androidtv", name: "Sony + テレビ")) == .androidTV(tv))
        try check("bootstrap rotation preserves labels and certificate pin", tv.replacingToken(String(repeating: "z", count: 43)).name == tv.name && tv.replacingToken(token).platform == "androidtv" && tv.replacingToken(token).fingerprint == pin)
        for base in [desktop, television] {
            try check("name may appear without optional platform", try PairingCode.parse(labeled(base, name: "TV & PC")) != PairingCode.parse(base))
            try rejects("duplicate name rejected", labeled(base, name: "one") + "&name=two")
            try rejects("encoded duplicate name rejected", labeled(base, name: "one") + "&%6Eame=two")
            try rejects("duplicate platform rejected", labeled(base, platform: base == desktop ? "windows" : "androidtv") + "&platform=windows")
            try rejects("unknown query rejected", base + "&brand=Sony")
            try rejects("unknown query with metadata rejected", labeled(base, name: "known") + "&extra=1")
            try rejects("missing token not rescued by metadata", labeled(base.replacingOccurrences(of: "&token=\(token)", with: ""), platform: base == desktop ? "windows" : "androidtv", name: "valid"))
            for name in ["", "   ", "\nValid", "Valid\r", "bad\u{7f}", "bad\u{85}", "bad\u{202e}", String(repeating: "a", count: 81), String(repeating: "🎮", count: 65)] {
                try rejects("invalid or oversized name rejected", labeled(base, name: name))
            }
            try check("80 ASCII scalar name accepted", (try? PairingCode.parse(labeled(base, name: String(repeating: "a", count: 80)))) != nil)
            try check("256 UTF8 byte name accepted", (try? PairingCode.parse(labeled(base, name: String(repeating: "🎮", count: 64)))) != nil)
            try rejects("user info stays forbidden", base.replacingOccurrences(of: "sofatap://", with: "sofatap://user@"))
            try rejects("path stays forbidden", base.replacingOccurrences(of: "?host", with: "/control?host"))
            try rejects("fragment stays forbidden", labeled(base, name: "name") + "#fragment")
            try rejects("short token stays forbidden", base.replacingOccurrences(of: token, with: "short"))
            try rejects("bad pin stays forbidden", base.replacingOccurrences(of: pin, with: String(repeating: "g", count: 64)))
        }
        try rejects("TV platform cannot enter desktop route", labeled(desktop, platform: "androidtv"))
        try rejects("desktop platform cannot enter TV route", labeled(television, platform: "windows"))
        try rejects("unsupported desktop platform", labeled(desktop, platform: "webos"))
        try rejects("unsupported TV platform", labeled(television, platform: "webos"))
        try rejects("case-sensitive platform allowlist", labeled(desktop, platform: "Windows"))
        try rejects("unknown QR namespace", television.replacingOccurrences(of: "//tv?", with: "//webos?"))
        try rejects("Android public IP remains rejected", television.replacingOccurrences(of: "192.168.1.8", with: "8.8.8.8"))
        try rejects("Android short legacy desktop token remains rejected", television.replacingOccurrences(of: token, with: String(repeating: "x", count: 32)))
        try check("desktop 32-byte token still accepted", (try? PairingCode.parse(desktop.replacingOccurrences(of: token, with: String(repeating: "x", count: 32)))) != nil)

        let hinted = try Pairing.parse(labeled(desktop, platform: "windows", name: "QR name"))
        var library = DeviceLibrary<Pairing>(); library.upsert(hinted)
        let id = library.selectedID!
        try check("new record uses QR hint immediately", library.selected?.displayName == "QR name" && library.selected?.platform == "windows")
        try library.rename(id, name: "My couch")
        try library.updateMetadata(id, name: "Authenticated PC", platform: "linux")
        library.upsert(try Pairing.parse(labeled(desktop, platform: "macos", name: "Scanned again")))
        try check("rescan cannot replace alias or authenticated metadata", library.selected?.displayName == "My couch" && library.selected?.reportedName == "Authenticated PC" && library.selected?.platform == "linux")
        try library.validate()
        let restored = try JSONDecoder().decode(DeviceLibrary<Pairing>.self, from: JSONEncoder().encode(library))
        try check("metadata and credentials survive library persistence", restored == library)
        let oldJSON = "{\"host\":\"192.168.1.7\",\"port\":53317,\"token\":\"\(token)\",\"fingerprint\":\"\(pin)\"}"
        try check("legacy stored computer credential still decodes", try JSONDecoder().decode(Pairing.self, from: Data(oldJSON.utf8)) == legacyPC)
        let oldTVJSON = oldJSON.replacingOccurrences(of: "192.168.1.7", with: "192.168.1.8").replacingOccurrences(of: "53317", with: "53319")
        try check("legacy stored TV credential still decodes", try JSONDecoder().decode(AndroidTVPairing.self, from: Data(oldTVJSON.utf8)) == legacyTV)
        var tvLibrary = DeviceLibrary<AndroidTVPairing>(); tvLibrary.upsert(tv.replacingToken(String(repeating: "r", count: 43)))
        try check("TV replacement credential stores initial QR name", tvLibrary.selected?.displayName == "Sony + テレビ" && tvLibrary.selected?.platform == "androidtv")
        try tvLibrary.updateMetadata(tvLibrary.selectedID!, name: "Authenticated TV", platform: "androidtv")
        try check("authenticated TV hello can replace QR hint", tvLibrary.selected?.displayName == "Authenticated TV")
        print("PASS \(count) unified QR routing, strict metadata, legacy and device-library checks; no network, Keychain or OS input")
    }
}
