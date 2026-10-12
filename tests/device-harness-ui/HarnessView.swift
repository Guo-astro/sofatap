import AppKit
import CoreGraphics
import Foundation

// This executable only draws a recording. It never creates or posts input events,
// requests Accessibility access, changes displays, or activates an application.
private struct HarnessError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct Options {
    var displayID: CGDirectDisplayID
    var state: URL
    var evidence: URL
    var duration: TimeInterval

    static func parse(_ arguments: [String]) throws -> Options {
        var values: [String: String] = [:]
        var index = 1
        let accepted = Set(["--display-id", "--state", "--evidence-dir", "--duration"])
        while index < arguments.count {
            let key = arguments[index]
            guard accepted.contains(key), index + 1 < arguments.count,
                  values[key] == nil else { throw HarnessError("Invalid or repeated option.") }
            values[key] = arguments[index + 1]
            index += 2
        }
        guard let rawID = values["--display-id"], let displayID = UInt32(rawID),
              let state = values["--state"], state.hasPrefix("/"),
              let evidence = values["--evidence-dir"], evidence.hasPrefix("/"),
              let duration = TimeInterval(values["--duration"] ?? "900"),
              duration > 0, duration <= 3600 else {
            throw HarnessError("Use --display-id <non-primary Yomado ID> --state <absolute state.json> --evidence-dir <new absolute directory> [--duration <1...3600 seconds>].")
        }
        return Options(displayID: displayID, state: URL(fileURLWithPath: state),
                       evidence: URL(fileURLWithPath: evidence, isDirectory: true), duration: duration)
    }
}

private struct Display: Codable, Equatable {
    let id: UInt32
    let main: Bool
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let vendor: UInt32
    let model: UInt32
    let pixelWidth: Int
    let pixelHeight: Int
    var yomado: Bool { vendor == 505 && model == 0x5644 }
}

private struct Snapshot: Codable {
    let capturedAt: String
    let displays: [Display]
    let cursorX: Double
    let cursorY: Double
    let foregroundPID: Int32?

    static func capture() throws -> Snapshot {
        var ids = [CGDirectDisplayID](repeating: 0, count: 64)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success,
              count > 0, count <= ids.count else { throw HarnessError("Could not read display topology.") }
        let displays = ids.prefix(Int(count)).map { id -> Display in
            let bounds = CGDisplayBounds(id)
            return Display(id: id, main: CGDisplayIsMain(id) != 0,
                x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height,
                vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                pixelWidth: CGDisplayPixelsWide(id), pixelHeight: CGDisplayPixelsHigh(id))
        }.sorted { $0.id < $1.id }
        // CGEvent(source:nil) reads current pointer state. It is never posted.
        guard let position = CGEvent(source: nil)?.location else {
            throw HarnessError("Could not read the current cursor position.")
        }
        return Snapshot(capturedAt: ISO8601DateFormatter().string(from: Date()), displays: displays,
                        cursorX: position.x, cursorY: position.y,
                        foregroundPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }
}

private struct DrawingState {
    var valid = false
    var notice = "Waiting for isolated recorder state…"
    var sequence = 0
    var width = 800.0
    var height = 500.0
    var pointer = CGPoint(x: 400, y: 250)
    var buttons: [String] = []
    var clicksLeft = 0
    var clicksRight = 0
    var scroll = CGPoint.zero
    var text = ""
    var focus = "notfocused"
    var revision = 0
    var releases = 0
    var lastAction = "none"
    var actions: [String: Int] = [:]
    var trail: [CGPoint] = []
    var topologyStatus = "Checking non-interference…"

    mutating func read(_ url: URL) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_048_576 else {
                throw HarnessError("State exceeds the size limit.")
            }
            let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
            guard bytes.count <= 1_048_576,
                  let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  (json["schemaVersion"] as? NSNumber)?.intValue == 1,
                  json["mode"] as? String == "isolated-recording-only",
                  json["osInjection"] as? Bool == false else {
                throw HarnessError("Refusing state that is not marked isolated-recording-only / osInjection=false.")
            }
            guard let w = json["width"] as? Double, let h = json["height"] as? Double,
                  w.isFinite, h.isFinite, w > 0, h > 0, w <= 16384, h <= 16384,
                  let p = json["pointer"] as? [String: Double],
                  let x = p["x"], let y = p["y"], x.isFinite, y.isFinite else {
                throw HarnessError("State dimensions or pointer are invalid.")
            }
            let nextSequence = (json["sequence"] as? NSNumber)?.intValue ?? 0
            let nextPoint = CGPoint(x: min(w, max(0, x)), y: min(h, max(0, y)))
            if !valid || nextSequence < sequence { trail.removeAll() }
            if trail.last != nextPoint { trail.append(nextPoint) }
            if trail.count > 512 { trail.removeFirst(trail.count - 512) }
            sequence = nextSequence; width = w; height = h; pointer = nextPoint
            buttons = (json["buttons"] as? [String] ?? []).filter { $0 == "left" || $0 == "right" }
            let clicks = json["clicks"] as? [String: Int] ?? [:]
            clicksLeft = clicks["left"] ?? 0; clicksRight = clicks["right"] ?? 0
            if let s = json["scroll"] as? [String: Double], let sx = s["x"], let sy = s["y"], sx.isFinite, sy.isFinite {
                scroll = CGPoint(x: min(1_000_000, max(-1_000_000, sx)), y: min(1_000_000, max(-1_000_000, sy)))
            }
            text = String((json["text"] as? String ?? "").prefix(16000))
            focus = String((json["focus"] as? String ?? "notfocused").prefix(32))
            revision = (json["focusRevision"] as? NSNumber)?.intValue ?? 0
            releases = (json["releases"] as? NSNumber)?.intValue ?? 0
            lastAction = String((json["lastAction"] as? String ?? "none").prefix(32))
            actions = json["actions"] as? [String: Int] ?? [:]
            valid = true
            notice = "Recorded phone actions → local drawing only"
        } catch {
            valid = false
            // Do not print raw state, file content or errors that could expose private data.
            notice = FileManager.default.fileExists(atPath: url.path)
                ? "State unavailable or invalid. No OS input is possible."
                : "Waiting for isolated recorder state…"
        }
    }
}

private final class HarnessPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HarnessCanvas: NSView {
    var state = DrawingState() { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    private let background = NSColor(calibratedRed: 0.067, green: 0.098, blue: 0.106, alpha: 1)
    private let surface = NSColor(calibratedRed: 0.118, green: 0.165, blue: 0.173, alpha: 1)
    private let mint = NSColor(calibratedRed: 0.596, green: 0.914, blue: 0.769, alpha: 1)
    private let muted = NSColor(calibratedRed: 0.659, green: 0.729, blue: 0.718, alpha: 1)

    private func label(_ text: String, at rect: NSRect, size: CGFloat = 14,
                       color: NSColor? = nil, weight: NSFont.Weight = .regular) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        (text as NSString).draw(in: rect, withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color ?? NSColor.white,
            .paragraphStyle: paragraph
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill(); bounds.fill()
        label("Sofatap · Device Test Harness", at: NSRect(x: 28, y: 23, width: bounds.width - 56, height: 34), size: 25, weight: .semibold)
        label("ISOLATED RECORDING ONLY · NO MAC MOUSE / KEYBOARD OUTPUT",
              at: NSRect(x: 28, y: 65, width: bounds.width - 56, height: 22), size: 12, color: mint, weight: .bold)
        label(state.notice, at: NSRect(x: 28, y: 93, width: bounds.width - 56, height: 25), color: muted)

        let canvas = NSRect(x: 28, y: 131, width: bounds.width - 344, height: bounds.height - 288)
        surface.setFill(); NSBezierPath(roundedRect: canvas, xRadius: 18, yRadius: 18).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: canvas, xRadius: 18, yRadius: 18).addClip()
        for y in stride(from: canvas.minY + 20, through: canvas.maxY, by: 24) {
            for x in stride(from: canvas.minX + 20, through: canvas.maxX, by: 24) {
                mint.withAlphaComponent(0.12).setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 2, height: 2)).fill()
            }
        }
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: canvas.minX + p.x / state.width * canvas.width,
                    y: canvas.minY + p.y / state.height * canvas.height)
        }
        if state.valid {
            let path = NSBezierPath()
            for (index, point) in state.trail.enumerated() {
                if index == 0 { path.move(to: map(point)) } else { path.line(to: map(point)) }
            }
            mint.withAlphaComponent(0.50).setStroke(); path.lineWidth = 2; path.stroke()
            let point = map(state.pointer)
            let radius: CGFloat = state.buttons.isEmpty ? 8 : 14
            mint.withAlphaComponent(0.14).setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48)).fill()
            mint.setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        label("Local drawn pointer · not the system cursor", at: NSRect(x: canvas.minX + 18, y: canvas.maxY - 35, width: canvas.width - 36, height: 20), size: 12, color: muted)

        let sx = canvas.maxX + 24
        label("Observed state", at: NSRect(x: sx, y: 134, width: 260, height: 26), size: 18, weight: .semibold)
        let details = [
            "Sequence   \(state.sequence)", "Last action   \(state.lastAction)",
            "Move   \(state.actions["move"] ?? 0)",
            "Left click   \(state.clicksLeft)", "Right click   \(state.clicksRight)",
            "Held buttons   \(state.buttons.isEmpty ? "none" : state.buttons.joined(separator: ", "))",
            "Button actions   \(state.actions["button"] ?? 0)",
            "Scroll   \(Int(state.scroll.x)), \(Int(state.scroll.y))",
            "Text / keys   \(state.actions["text"] ?? 0) / \(state.actions["key"] ?? 0)",
            "Focus   \(state.focus) · \(state.revision)", "Releases   \(state.releases)"
        ]
        for (index, value) in details.enumerated() {
            label(value, at: NSRect(x: sx, y: 175 + CGFloat(index) * 27, width: 264, height: 26), size: 13, color: muted)
        }
        let textRect = NSRect(x: 28, y: bounds.height - 138, width: bounds.width - 56, height: 81)
        surface.setFill(); NSBezierPath(roundedRect: textRect, xRadius: 12, yRadius: 12).fill()
        label(state.text.isEmpty ? "Recorded test text will appear here. This is not a native editable field." : state.text,
              at: textRect.insetBy(dx: 14, dy: 12), size: 15, color: state.text.isEmpty ? muted : .white)
        label(state.topologyStatus, at: NSRect(x: 28, y: bounds.height - 38, width: bounds.width - 56, height: 25), size: 11, color: muted)
    }
}

private final class HarnessDelegate: NSObject, NSApplicationDelegate {
    let options: Options
    let before: Snapshot
    var window: HarnessPanel?
    var timer: Timer?
    var canvas = HarnessCanvas()
    var shownAt: Date?
    var settled = false
    var exitReason = "duration_elapsed"

    init(options: Options, before: Snapshot) { self.options = options; self.before = before }

    private func write<T: Encodable>(_ value: T, name: String) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let destination = options.evidence.appendingPathComponent(name)
        try encoder.encode(value).write(to: destination, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    private func screen() throws -> NSScreen {
        guard let display = try Snapshot.capture().displays.first(where: { $0.id == options.displayID }),
              !display.main, display.yomado,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == options.displayID
              }) else { throw HarnessError("Requested display must be an active non-primary Yomado display.") }
        return screen
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard NSApp.activationPolicy() == .prohibited else {
                throw HarnessError("Application activation is not prohibited.")
            }
            let target = try screen()
            let available = target.visibleFrame.insetBy(dx: 24, dy: 24)
            guard available.width >= 950, available.height >= 620 else {
                throw HarnessError("Virtual display is too small for the isolated canvas.")
            }
            let size = NSSize(width: min(1120, available.width), height: min(800, available.height))
            let frame = NSRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                               width: size.width, height: size.height)
            let panel = HarnessPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false, screen: target)
            panel.title = "Sofatap — isolated device test harness"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.hasShadow = true
            panel.backgroundColor = .black
            panel.collectionBehavior = [.stationary, .ignoresCycle]
            panel.setFrame(frame, display: false)
            canvas.frame = NSRect(origin: .zero, size: size)
            panel.contentView = canvas
            window = panel
            // The only show call. The panel cannot become key/main and ignores all mouse input.
            panel.orderFrontRegardless()
            shownAt = Date()
            try write(before, name: "before.json")
            timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
            tick()
        } catch {
            exitReason = "startup_refused"
            fputs("Harness refused startup: display validation or evidence write failed.\n", stderr)
            NSApp.terminate(nil)
        }
    }

    private func tick() {
        do {
            guard NSApp.activationPolicy() == .prohibited else {
                exitReason = "activation_policy_changed"
                NSApp.terminate(nil); return
            }
            let now = try Snapshot.capture()
            guard now.displays == before.displays else {
                exitReason = "display_topology_changed"
                NSApp.terminate(nil); return
            }
            _ = try screen()
            guard let window, !window.isKeyWindow, !window.isMainWindow,
                  let screen = window.screen,
                  (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == options.displayID,
                  screen.frame.contains(window.frame) else {
                exitReason = "window_isolation_check_failed"
                NSApp.terminate(nil); return
            }
            var value = canvas.state
            value.read(options.state)
            if !settled, Date().timeIntervalSince(shownAt ?? Date()) >= 0.6 {
                try write(now, name: "after-show.json")
                let cursorUnchanged = now.cursorX == before.cursorX && now.cursorY == before.cursorY
                let focusUnchanged = now.foregroundPID == before.foregroundPID
                let proof = [
                    "topologyUnchanged": now.displays == before.displays,
                    "physicalTopologyUnchanged": now.displays.filter { !$0.yomado } == before.displays.filter { !$0.yomado },
                    "cursorUnchangedAtSample": cursorUnchanged,
                    "foregroundUnchangedAtSample": focusUnchanged,
                    "activationPolicyProhibited": NSApp.activationPolicy() == .prohibited,
                    "windowIsKey": window.isKeyWindow, "windowIsMain": window.isMainWindow,
                    "windowOnRequestedVirtualDisplay": true, "osInputInjection": false,
                    "screenshotOrInputDeliveryProof": false
                ]
                try write(proof, name: "show-verification.json")
                try write([
                    "windowNumber": Double(window.windowNumber), "processID": Double(ProcessInfo.processInfo.processIdentifier),
                    "displayID": Double(options.displayID), "appKitX": window.frame.minX, "appKitY": window.frame.minY,
                    "width": window.frame.width, "height": window.frame.height
                ], name: "window.json")
                guard focusUnchanged else {
                    // A user app switch may explain this, but this run cannot prove
                    // non-interference. Keep the evidence and close only our own panel.
                    exitReason = "foreground_changed_during_show_check"
                    NSApp.terminate(nil); return
                }
                value.topologyStatus = "Virtual display \(options.displayID) · topology unchanged · cursor sample \(cursorUnchanged ? "unchanged" : "changed externally / cause unverified") · foreground sample \(focusUnchanged ? "unchanged" : "changed / cause unverified")"
                settled = true
            }
            canvas.state = value
            if Date().timeIntervalSince(shownAt ?? Date()) >= options.duration { NSApp.terminate(nil) }
        } catch {
            exitReason = "read_only_monitor_failed"
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); timer = nil
        window?.orderOut(nil)
        window?.close(); window = nil
        if let after = try? Snapshot.capture() { try? write(after, name: "after-close.json") }
        try? write(["reason": exitReason, "restoration": "No display, focus, cursor, user-window or input changes were requested."], name: "completion.json")
    }
}

@main
private enum Main {
    static func main() {
        do {
            let options = try Options.parse(CommandLine.arguments)
            let before = try Snapshot.capture()
            guard before.displays.contains(where: { $0.id == options.displayID && !$0.main && $0.yomado }) else {
                throw HarnessError("Requested display must be an active non-primary Yomado display.")
            }
            guard !FileManager.default.fileExists(atPath: options.evidence.path) else {
                throw HarnessError("Evidence directory must be new; existing results are never overwritten.")
            }
            try FileManager.default.createDirectory(at: options.evidence, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let app = NSApplication.shared
            // A CLI may already have the prohibited policy. Do not interpret the
            // setter's return value as the policy; read and verify the actual state.
            if app.activationPolicy() != .prohibited { _ = app.setActivationPolicy(.prohibited) }
            guard app.activationPolicy() == .prohibited else {
                throw HarnessError("Activation policy is \(app.activationPolicy().rawValue); prohibited policy is required.")
            }
            let delegate = HarnessDelegate(options: options, before: before)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        } catch let error as HarnessError {
            fputs("\(error.description)\n", stderr)
            exit(64)
        } catch {
            fputs("Harness preparation failed. No GUI or OS input was requested.\n", stderr)
            exit(1)
        }
    }
}
