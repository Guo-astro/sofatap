import Foundation

/// Manual LAN selection only. Discovery, TLS pinning and user consent belong to the session layer.
struct WebOSTVEndpoint: Equatable, Sendable {
    let host: String
    var controlURL: URL { URL(string: "wss://\(host):3001")! }

    init(host: String) throws { try self.init(host: host, allowLoopback: false) }

    /// Explicit opt-in for local protocol fixtures; production UI must use init(host:).
    init(host: String, allowLoopback: Bool) throws {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ part in
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) } &&
            (part.count == 1 || part.first != "0") && UInt8(part) != nil
        }) else { throw WebOSTVProtocolError.invalidEndpoint }
        let octets = parts.compactMap { UInt8($0) }
        let privateLAN = octets[0] == 10 ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168)
        guard privateLAN || (allowLoopback && host == "127.0.0.1") else {
            throw WebOSTVProtocolError.invalidEndpoint
        }
        self.host = host
    }

    func pointerURL(_ raw: String) throws -> URL {
        guard raw.utf8.count <= 512, raw.utf8.allSatisfy({ (33...126).contains($0) }),
              let parts = URLComponents(string: raw), parts.host == host,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              (parts.scheme == "wss" && parts.port == 3001) || (parts.scheme == "ws" && parts.port == 3000),
              raw == "\(parts.scheme!)://\(host):\(parts.port!)\(parts.percentEncodedPath)",
              Self.validPointerPath(parts.percentEncodedPath) else {
            throw WebOSTVProtocolError.invalidPointerEndpoint
        }
        // Some TVs advertise the legacy ws:3000 pointer URL even over TLS. Retain
        // the exact allowlisted path, but always connect via the pinned wss:3001 endpoint.
        return URL(string: "wss://\(host):3001\(parts.percentEncodedPath)")!
    }

    private static func validPointerPath(_ path: String) -> Bool {
        if path == "/netinput.pointer.sock" { return true }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 4 && parts[0].isEmpty && parts[1] == "resources" &&
            parts[3] == "netinput.pointer.sock" && (1...128).contains(parts[2].utf8.count) &&
            parts[2].utf8.allSatisfy { WebOSTVProtocol.isIdentifierByte($0) }
    }
}

enum WebOSTVExpectedResponse: Equatable, Sendable {
    case none, registration(id: String), pointerSocket(id: String)
    var id: String? {
        switch self { case .none: nil; case .registration(let id), .pointerSocket(let id): id }
    }
}

/// Do not log the associated client key or pointer resource path.
enum WebOSTVResponse: Equatable, Sendable, CustomStringConvertible {
    case registered(clientKey: String), pointerSocket(URL), error(code: Int?), other
    var description: String {
        switch self {
        case .registered: "webOS registered (key redacted)"
        case .pointerSocket: "webOS pointer endpoint (path redacted)"
        case .error(let code): "webOS request rejected (\(code.map(String.init) ?? "unknown"))"
        case .other: "webOS other response"
        }
    }
}

enum WebOSTVButton: String, CaseIterable, Sendable {
    case back = "BACK", home = "HOME", up = "UP", down = "DOWN"
    case left = "LEFT", right = "RIGHT", enter = "ENTER"
}

enum WebOSTVPointerAction: Equatable, Sendable {
    case move(dx: Double, dy: Double), click, scroll(dx: Double, dy: Double), button(WebOSTVButton)
}

enum WebOSTVProtocolError: Error, LocalizedError, Equatable {
    case invalidEndpoint, invalidPointerEndpoint, invalidIdentifier, invalidClientKey
    case malformedMessage, messageTooLarge, unexpectedResponse, invalidMotion

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Enter a private IPv4 address for the TV."
        case .invalidPointerEndpoint: "The TV returned an unsupported pointer endpoint."
        case .invalidIdentifier: "The TV request identifier is invalid."
        case .invalidClientKey: "The TV pairing key is invalid."
        case .malformedMessage: "The TV returned an invalid message."
        case .messageTooLarge: "The TV message exceeds the size limit."
        case .unexpectedResponse: "The TV response does not match a pending request."
        case .invalidMotion: "The TV pointer movement exceeds the allowed range."
        }
    }
}

/// Pure protocol implementation, based on LG's Connect SDK sources:
/// https://github.com/ConnectSDK/Connect-SDK-Android-Core/blob/master/src/com/connectsdk/service/webos/WebOSTVDeviceService.java
/// https://github.com/ConnectSDK/Connect-SDK-Android-Core/blob/master/src/com/connectsdk/service/webos/WebOSTVServiceSocketClient.java
/// https://github.com/ConnectSDK/Connect-SDK-Android-Core/blob/master/src/com/connectsdk/service/webos/WebOSTVMouseSocketConnection.java
/// This does not establish compatibility with an actual TV or grant authorization.
enum WebOSTVProtocol {
    static let maximumMessageBytes = 16_384
    static let maximumMotion = 500.0
    static let maximumScroll = 1_200.0

    static func registration(id: String, clientKey: String? = nil) throws -> String {
        try validateIdentifier(id)
        var payload: [String: Any] = [
            "pairingType": "PROMPT",
            "manifest": ["manifestVersion": 1, "permissions": ["CONTROL_MOUSE_AND_KEYBOARD"]]
        ]
        if let clientKey { try validateClientKey(clientKey); payload["client-key"] = clientKey }
        return try encodeJSON(["type": "register", "id": id, "payload": payload])
    }

    static func pointerRequest(id: String) throws -> String {
        try validateIdentifier(id)
        return try encodeJSON(["type": "request", "id": id,
            "uri": "ssap://com.webos.service.networkinput/getPointerInputSocket"])
    }

    static func parse(_ text: String, endpoint: WebOSTVEndpoint,
                      expecting: WebOSTVExpectedResponse) throws -> WebOSTVResponse {
        guard text.utf8.count <= maximumMessageBytes else { throw WebOSTVProtocolError.messageTooLarge }
        if let id = expecting.id { try validateIdentifier(id) }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { throw WebOSTVProtocolError.malformedMessage }
        guard ["registered", "response", "error"].contains(type) else { return .other }
        if type == "registered", object["id"] == nil {
            // Some LG firmwares omit the registration ID. Only an exclusive,
            // outstanding registration phase may accept that reply; a connection
            // with no pending registration must never adopt an unsolicited key.
            guard case .registration = expecting else { throw WebOSTVProtocolError.unexpectedResponse }
        } else {
            guard let id = object["id"] as? String else { throw WebOSTVProtocolError.unexpectedResponse }
            try validateIdentifier(id)
            guard id == expecting.id else { throw WebOSTVProtocolError.unexpectedResponse }
        }
        if type == "error" {
            // Extract only a bounded numeric status. Never relay server text, which
            // can contain credentials or untrusted instructions, into UI or logs.
            let first = (object["error"] as? String)?.split(separator: " ").first
            let code = first.flatMap { Int($0) }.flatMap { (100...599).contains($0) ? $0 : nil }
            return .error(code: code)
        }
        guard let payload = object["payload"] as? [String: Any] else { throw WebOSTVProtocolError.malformedMessage }
        if type == "registered" {
            guard case .registration = expecting else { throw WebOSTVProtocolError.unexpectedResponse }
            guard let key = payload["client-key"] as? String else { throw WebOSTVProtocolError.invalidClientKey }
            try validateClientKey(key)
            return .registered(clientKey: key)
        }
        if case .registration = expecting {
            // PROMPT is an intermediate response, not completed authorization.
            if payload["pairingType"] as? String == "PROMPT" { return .other }
            throw WebOSTVProtocolError.unexpectedResponse
        }
        guard case .pointerSocket = expecting else { throw WebOSTVProtocolError.unexpectedResponse }
        // LG's SDK consumes socketPath directly; returnValue is not present on
        // every firmware. When supplied it must be an actual JSON true boolean.
        if let value = payload["returnValue"] {
            guard let accepted = value as? NSNumber,
                  String(cString: accepted.objCType) == "c", accepted.boolValue else {
                throw WebOSTVProtocolError.malformedMessage
            }
        }
        guard let raw = payload["socketPath"] as? String else { throw WebOSTVProtocolError.invalidPointerEndpoint }
        return .pointerSocket(try endpoint.pointerURL(raw))
    }

    static func encode(_ action: WebOSTVPointerAction) throws -> String {
        switch action {
        case .click: return "type:click\n\n"
        case .button(let button): return "type:button\nname:\(button.rawValue)\n\n"
        case .move(let dx, let dy):
            try validateMotion(dx, dy, bound: maximumMotion)
            return "type:move\ndx:\(number(dx))\ndy:\(number(dy))\ndown:0\n\n"
        case .scroll(let dx, let dy):
            try validateMotion(dx, dy, bound: maximumScroll)
            return "type:scroll\ndx:\(number(dx))\ndy:\(number(dy))\n\n"
        }
    }

    private static func validateMotion(_ dx: Double, _ dy: Double, bound: Double) throws {
        guard dx.isFinite, dy.isFinite, abs(dx) <= bound, abs(dy) <= bound else {
            throw WebOSTVProtocolError.invalidMotion
        }
    }
    private static func number(_ value: Double) -> String { value == 0 ? "0" : String(value) }
    fileprivate static func isIdentifierByte(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
    }
    private static func validateIdentifier(_ id: String) throws {
        guard (1...64).contains(id.utf8.count), id.utf8.allSatisfy(isIdentifierByte) else {
            throw WebOSTVProtocolError.invalidIdentifier
        }
    }
    private static func validateClientKey(_ key: String) throws {
        guard (1...256).contains(key.utf8.count), key.utf8.allSatisfy({
            isIdentifierByte($0) || $0 == 43 || $0 == 47 || $0 == 61
        }) else { throw WebOSTVProtocolError.invalidClientKey }
    }
    private static func encodeJSON(_ object: [String: Any]) throws -> String {
        // Objects here contain only bounded, validated strings and constant fields.
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              data.count <= maximumMessageBytes, let text = String(data: data, encoding: .utf8) else {
            throw WebOSTVProtocolError.malformedMessage
        }
        return text
    }
}
