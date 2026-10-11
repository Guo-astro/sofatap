import Foundation

enum ReceiverProtocolError: Error {
    case oversizedFrame, truncatedFrame, invalidState
}

/// Bounds a newline-delimited JSON frame before JSON/base64 decoding. Pairing secrets stay in memory.
struct ReceiverLineBuffer {
    static let maximumFrameBytes = 2 * 1_024 * 1_024
    private var bytes = Data()

    mutating func append(_ byte: UInt8) throws -> Data? {
        if byte == 10 {
            let frame = bytes
            bytes.removeAll(keepingCapacity: true)
            return frame.isEmpty ? nil : frame
        }
        guard bytes.count < Self.maximumFrameBytes else { throw ReceiverProtocolError.oversizedFrame }
        bytes.append(byte)
        return nil
    }

    func finish() throws {
        guard bytes.isEmpty else { throw ReceiverProtocolError.truncatedFrame }
    }
}

struct ReceiverPairing: Decodable, Equatable, Sendable, Identifiable {
    let host: String
    let uri: String
    let qrPng: String
    var id: String { host }

    var pngData: Data? { Data(base64Encoded: qrPng) }

    func validate() throws {
        guard !host.isEmpty, host.utf8.count <= 253,
              !host.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              uri.utf8.count <= 4_096,
              let components = URLComponents(string: uri),
              components.scheme == "sofatap", components.host == "pair",
              qrPng.utf8.count <= 256 * 1_024,
              let png = pngData, png.count >= 24,
              Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10],
              Array(png[12..<16]) == [73, 72, 68, 82] else {
            throw ReceiverProtocolError.invalidState
        }
        // Check the PNG dimensions before handing data to an image decoder.
        let width = png[16..<20].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let height = png[20..<24].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard width > 0, height > 0, width <= 2_048, height <= 2_048 else {
            throw ReceiverProtocolError.invalidState
        }
    }
}

struct ReceiverState: Decodable, Equatable, Sendable {
    let type: String
    let name: String
    let platform: String
    let inputStatus: String
    let dryRun: Bool
    let connected: Bool
    let pairings: [ReceiverPairing]

    static func decode(_ data: Data) throws -> ReceiverState {
        guard data.count <= ReceiverLineBuffer.maximumFrameBytes else { throw ReceiverProtocolError.oversizedFrame }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.type == "state", value.platform == "macos",
              !value.name.isEmpty, value.name.utf8.count <= 512,
              value.inputStatus.utf8.count <= 128, value.pairings.count <= 16,
              Set(value.pairings.map(\.host)).count == value.pairings.count else {
            throw ReceiverProtocolError.invalidState
        }
        try value.pairings.forEach { try $0.validate() }
        return value
    }

    /// Preserve the selected interface across periodic updates, but never keep a stale pairing.
    func selectedHost(preserving current: String?) -> String? {
        if let current, pairings.contains(where: { $0.host == current }) { return current }
        return pairings.first?.host
    }
}

enum ReceiverCommand: String, Sendable, CaseIterable {
    case refresh, requestAccess, quit

    var line: Data { Data("{\"type\":\"\(rawValue)\"}\n".utf8) }
}
