// Reproducible offscreen layout fixtures for the production ReceiverContent view.
// No NSApplication, window, controller, receiver backend, network or clipboard is started.
// Build from the repository root:
// xcrun swiftc -parse-as-library -swift-version 5 -D SOFATAP_UI_FIXTURE \
//   -target arm64-apple-macosx15.0 desktop/macos/*.swift \
//   desktop/macos/tests/ReceiverAppearanceFixtures.swift -o /tmp/sofatap-appearance-fixtures
// /tmp/sofatap-appearance-fixtures artifacts/mint-calm
import AppKit
import CoreImage
import Foundation
import SwiftUI
import Vision

@main
struct ReceiverAppearanceFixtures {
    @MainActor static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "artifacts/mint-calm", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let qrData = try demoQR()
        let qrChecks = try verifyQRRendering(qrData, destination: destination)
        let qr = qrData.base64EncodedString()
        let pairing = ReceiverPairing(host: "192.0.2.24", uri: "fixture://not-a-pairing-link", qrPng: qr)
        let longHost = "2001:db8:1234:5678:abcd:1234:abcd:5678"
        let secondPairing = ReceiverPairing(host: longHost, uri: "fixture://not-a-pairing-link", qrPng: qr)
        let states = [
            Fixture(name: "ready", width: 470, height: 700, state: state("ready", pairings: [pairing])),
            Fixture(name: "connected", width: 470, height: 700, state: state("ready", connected: true, pairings: [pairing])),
            Fixture(name: "permission-narrow", width: 440, height: 700,
                    state: state("accessibility_required", pairings: [pairing]),
                    accessNotice: "请在系统提示中打开设置，并允许 Sofatap Receiver。若没有出现提示，可点“打开系统设置”；列表中没有应用时，点 + 选择已安装的 Sofatap Receiver.app。系统可能要求密码或 Touch ID。授权后请回到这里重新检查。"),
            Fixture(name: "dry-run", width: 470, height: 700, state: state("dry_run", dryRun: true, pairings: [pairing])),
            Fixture(name: "desktop-unavailable", width: 440, height: 700, state: state("desktop_unavailable", connected: true, pairings: [pairing])),
            Fixture(name: "long-device-network", width: 440, height: 700,
                    state: state("ready", name: "客厅工作站 — 一台名称很长的 Mac 电脑", pairings: [secondPairing, pairing])),
            Fixture(name: "no-network", width: 470, height: 700, state: state("ready", pairings: [])),
            Fixture(name: "failure", width: 440, height: 700, state: state("ready", pairings: [pairing]), failure: "与 Mac 接收组件的连接已中断。请重新打开 Sofatap。"),
            Fixture(name: "starting", width: 470, height: 700, isStarting: true),
            Fixture(name: "stopping", width: 470, height: 700, state: state("ready", pairings: [pairing]), isStopping: true),
        ]
        var manifest: [[String: Any]] = []
        for fixture in states {
            let selected = fixture.state?.pairings.first
            let content = ReceiverContent(
                state: fixture.state, selectedPairing: selected,
                selectedHost: .constant(selected?.host), failure: fixture.failure,
                isStarting: fixture.isStarting, isStopping: fixture.isStopping,
                copied: false, accessRequested: fixture.accessNotice != nil,
                accessNotice: fixture.accessNotice,
                refresh: {}, requestAccess: {}, openAccessibilitySettings: {}, copyPairing: {}, quit: {}
            )
            // Measure the shared content at the requested width. Extra height in
            // permission fixtures records wrapped content, not a tested scroll view.
            let measurement = ImageRenderer(content: content)
            measurement.proposedSize = ProposedViewSize(width: fixture.width, height: nil)
            measurement.scale = 1
            guard let measured = measurement.cgImage else { throw FixtureError.renderFailed(fixture.name) }
            let contentHeight = max(fixture.height, Double(measured.height))
            let labeled = VStack(spacing: 0) {
                content.frame(width: fixture.width, height: contentHeight, alignment: .top)
                    .background(Color(red: 17 / 255, green: 25 / 255, blue: 27 / 255))
                Text("离屏布局 fixture · 非实机 · 测试二维码不可配对")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .frame(width: fixture.width, height: 28)
                    .background(Color(red: 0.2, green: 0.25, blue: 0.26))
            }
            let renderer = ImageRenderer(content: labeled)
            renderer.proposedSize = ProposedViewSize(width: fixture.width, height: contentHeight + 28)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw FixtureError.renderFailed(fixture.name)
            }
            let filename = "macos-\(fixture.name).png"
            try data.write(to: destination.appendingPathComponent(filename), options: .atomic)
            manifest.append([
                "file": filename,
                "contentWidth": fixture.width,
                "contentHeight": contentHeight,
                "naturalContentHeight": measured.height,
                "minimumFixtureHeight": fixture.height,
                "scale": 2,
                "renderer": "SwiftUI ImageRenderer using production ReceiverContent",
                "physicalAcceptance": false,
                "pairingCredentials": false,
                "note": "Offscreen fixture; native AppKit title bar, ScrollView container and interaction are not captured. The collapsed native picker renders; its open menu and keyboard interaction are not tested."
            ])
        }
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destination.appendingPathComponent("macos-fixtures.json"), options: .atomic)
        print("Rendered \(states.count) production-view offscreen fixtures; \(qrChecks) QR sharpness/readback checks passed. No receiver or native window was launched.")
    }

    static func state(_ inputStatus: String, name: String = "客厅电脑", connected: Bool = false,
                      dryRun: Bool = false, pairings: [ReceiverPairing]) -> ReceiverState {
        ReceiverState(type: "state", name: name, platform: "macos", inputStatus: inputStatus,
                      dryRun: dryRun, connected: connected, pairings: pairings)
    }

    /// Test the same QR view used by the receiver using the unscaled, one-pixel-per-
    /// module source. Upscaling the fixture itself would hide NSImage interpolation.
    @MainActor static func verifyQRRendering(_ png: Data, destination: URL) throws -> Int {
        guard let source = ReceiverQRCode.decode(png) else { throw FixtureError.qrFailed }
        var reports: [[String: Any]] = []
        for scale in [1.0, 2.0] {
            let renderer = ImageRenderer(content: ReceiverQRCode(image: source).background(.white))
            renderer.proposedSize = ProposedViewSize(width: 224, height: 224)
            renderer.scale = scale
            renderer.isOpaque = true
            guard let image = renderer.cgImage else { throw FixtureError.qrFailed }
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            try pixels.withUnsafeMutableBytes { storage in
                guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw FixtureError.qrFailed
                }
                context.interpolationQuality = .none
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            var intermediatePixels = 0
            for index in stride(from: 0, to: pixels.count, by: 4) {
                let rgb = pixels[index..<(index + 3)]
                if !rgb.allSatisfy({ $0 <= 1 }) && !rgb.allSatisfy({ $0 >= 254 }) {
                    intermediatePixels += 1
                }
            }
            guard intermediatePixels == 0 else {
                throw FixtureError.blurredQR(scale, intermediatePixels)
            }
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            guard request.results?.compactMap(\.payloadStringValue) == [demoPayload] else {
                throw FixtureError.qrReadbackFailed(scale)
            }
            reports.append([
                "scale": scale, "sourceWidth": source.width, "sourceHeight": source.height,
                "renderedWidth": width, "renderedHeight": height,
                "intermediatePixels": intermediatePixels, "decodedFixturePayloadMatches": true
            ])
        }
        let data = try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destination.appendingPathComponent("macos-qr-render-checks.json"), options: .atomic)
        return reports.count * 2
    }

    private static let demoPayload = "Sofatap UI fixture. This is not a pairing code."

    static func demoQR() throws -> Data {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw FixtureError.qrFailed }
        filter.setValue(Data(demoPayload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let image = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(output, from: output.extent),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw FixtureError.qrFailed
        }
        return data
    }
}

private struct Fixture {
    let name: String
    let width: Double
    let height: Double
    var state: ReceiverState? = nil
    var failure: String? = nil
    var isStarting = false
    var isStopping = false
    var accessNotice: String? = nil
}

private enum FixtureError: Error {
    case qrFailed
    case blurredQR(Double, Int)
    case qrReadbackFailed(Double)
    case renderFailed(String)
}
