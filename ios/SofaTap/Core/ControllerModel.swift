import Foundation
import SwiftUI
import CoreMotion
import UIKit
import CryptoKit

enum TextDelivery: Equatable {
    case ready, sending, sent, rejected(String), uncertain
}

private enum CommandResult {
    case accepted([String: Any]), rejected(String), uncertain
}

@MainActor
final class ControllerModel: ObservableObject {
    // A TV selection suspends the desktop transport, including scene/deep-link
    // reconnects. Input must never fall back to a different device on failure.
    @Published private(set) var desktopControlEnabled = true
    @Published private(set) var pairing: Pairing?
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var inputAvailable = false
    @Published private(set) var receiverState = ReceiverState()
    @Published private(set) var computerName = String(localized: "客厅电脑")
    @Published var notice = String(localized: "配对一次，坐下来就能控制电脑。")
    @Published var pairingError: String?
    @Published var draft: String {
        didSet {
            // Local-only recovery for a Typeless app switch or process termination.
#if SOFATAP_CONTROLLER_TESTING
            if testSend == nil && testLiveSend == nil && !demo && !ephemeralDraft { UserDefaults.standard.set(draft, forKey: "localTextDraft") }
#else
            if !demo && !ephemeralDraft { UserDefaults.standard.set(draft, forKey: "localTextDraft") }
#endif
            if textDelivery == .sent && draft != lastSentDraft { textDelivery = .ready }
        }
    }
    @Published var composing = false
    @Published var draftSelection = NSRange(location: 0, length: 0)
    @Published private(set) var liveTextStatus: LiveTextStatus = .idle
    private var ephemeralDraft = false
    private var liveTextSession: String?
    private var liveTextRevision = 0
    private var liveTextBaseline: LiveTextSnapshot?
    private var liveTextDesired: LiveTextSnapshot?
    private var liveTextEpoch = UUID()
    private var liveTextOpenCallbacks: [() -> Void] = []
    private var liveTextOpeningSnapshot: LiveTextSnapshot?

    @Published private(set) var textDelivery: TextDelivery = .ready {
        didSet { persistDeliveryState() }
    }
    @Published private(set) var dragging = false
    @Published private(set) var airMoving = false
    @Published var sensitivity = 1.0
    let demo: Bool
    let unlock = ComputerUnlockController()

    private var lastSentDraft: String?
    private var sentSnapshot = ""
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var sessionDelegate: PinnedSessionDelegate?
    private var generation = UUID()
    private var foreground = true
    private var keepAliveTask: Task<Void, Never>?
    private var helloTimeout: Task<Void, Never>?
    private var motionTimer: Timer?
    private var motionBusy = false
    // Keep the remote button down until its final queued movement is acknowledged.
    @Published private var dragReleasePending = false
    private var dragTail: (dx: Double, dy: Double)?
    private var scrollBusy = false
    private var queuedDX = 0.0
    private var queuedDY = 0.0
    private var queuedScroll = 0.0
    private var lastMovement = Date.distantPast
    private var lastScroll = Date.distantPast
    private let motion = CMMotionManager()
    private struct Pending {
        let type: String
        let timer: Task<Void, Never>
        let completion: ((CommandResult) -> Void)?
    }
    private var pending: [String: Pending] = [:]
#if SOFATAP_CONTROLLER_TESTING
    // Recording transport only: compiled solely by the offscreen regression test.
    private var testLiveSend: ((String, [String: Any], @escaping ([String: Any]) -> Void) -> Void)?
    private var testSend: ((String, [String: Any], @escaping (Bool) -> Void) -> Void)?
    init(testSend: @escaping (String, [String: Any], @escaping (Bool) -> Void) -> Void) {
        demo = false
        pairing = nil
        draft = ""
        connected = true
        inputAvailable = true
        self.testSend = testSend
    }
    init(testLiveSend: @escaping (String, [String: Any], @escaping ([String: Any]) -> Void) -> Void) {
        demo = false; pairing = nil; draft = ""; connected = true; inputAvailable = true
        receiverState = ReceiverState(platform: .windows, status: .ready, inputAvailable: true,
                                      textFocus: .editable, reportsTextFocus: true, supportsLiveText: true)
        self.testLiveSend = testLiveSend
    }
    func testFlushMovement() { flushMovement() }
    func testReceiveFocus(_ revision: Int, editable: Bool = true) {
        var state = receiverState; state.focusRevision = revision; state.textFocus = editable ? .editable : .other
        updateReceiverState(state)
    }
#endif

    init(demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo")) {
        self.demo = demo
        self.desktopControlEnabled = demo || UserDefaults.standard.string(forKey: "manualRemoteTarget") != "webos"
        self.pairing = demo ? nil : PairingStore.read()
        self.draft = demo ? String(localized: "你好，帮我播放今晚想看的电影。") : UserDefaults.standard.string(forKey: "localTextDraft") ?? ""
        unlock.setPairing(self.pairing)
        if demo { notice = String(localized: "界面演示：按钮只展示反馈，没有连接或操作电脑。") }
        else if let marker = UserDefaults.standard.string(forKey: "textDeliveryMarker") {
            // A process kill must never turn a pending/accepted draft into an implicit retry.
            if marker == "sent", UserDefaults.standard.string(forKey: "sentDraftDigest") == digest(draft) {
                lastSentDraft = draft
                textDelivery = .sent
            } else {
                textDelivery = .uncertain
            }
        }
    }

    // Session/permission availability is stable while a final drag ACK is pending.
    // The UI uses this for disconnect cleanup; canControl gates new input only.
    var controlAvailable: Bool { desktopControlEnabled && (demo || (connected && inputAvailable)) }
    var canControl: Bool { controlAvailable && !dragReleasePending }
    var remoteTextFocus: RemoteTextFocus { controlAvailable ? receiverState.textFocus : .unknown }
    var focusRevision: Int { receiverState.focusRevision }
    var statusTitle: String {
        if demo { return String(localized: "界面演示") }
        if connecting { return String(localized: "正在安全连接…") }
        if connected { return inputAvailable ? computerName : receiverState.unavailableTitle }
        return pairing == nil ? String(localized: "尚未配对电脑") : String(localized: "已配对 · 未连接")
    }
    var statusSubtitle: String {
        if demo { return String(localized: "未连接电脑 · SIMULATOR DEMO") }
        if let pairing { return String(localized: "\(pairing.host):\(pairing.port) · 证书固定") }
        return String(localized: "iPhone 和电脑连接同一家庭网络")
    }
    var draftLength: Int { draft.utf16.count }
    var draftWithinLimit: Bool { draftLength <= 16_000 }
    var sendingText: Bool { textDelivery == .sending }
    var usesLiveText: Bool { !demo && ((receiverState.supportsLiveText && liveTextStatus != .unsupported) || liveTextPaused) }
    var liveTextReady: Bool { liveTextStatus == .active || liveTextStatus == .syncing }
    var liveTextPaused: Bool { if case .paused = liveTextStatus { return true }; return false }
    var editorLoading: Bool { liveTextStatus == .starting }
    var liveTextDescription: String {
        switch liveTextStatus {
        case .idle: return String(localized: "点键盘或麦克风，开始同步当前输入框。")
        case .starting: return String(localized: "正在读取电脑当前输入框…")
        case .active: return String(localized: "已实时同步 · 退格、选区和全选也会同步。")
        case .syncing: return String(localized: "正在实时同步…")
        case .unsupported: return String(localized: "这个输入框不支持实时编辑，请确认后发送。")
        case .paused: return String(localized: "同步已暂停，手机文字已保留。检查电脑后重新读取输入框。")
        }
    }
    var canSendText: Bool {
        !usesLiveText && canControl && !draft.isEmpty && draftWithinLimit && !composing && !sendingText &&
        textDelivery != .uncertain && !(textDelivery == .sent && draft == lastSentDraft)
    }
    var textStatus: String {
        if usesLiveText { return liveTextDescription }
        if composing { return String(localized: "正在输入或听写，完成后再发送。") }
        if !draftWithinLimit { return String(localized: "文字超过 16,000 字符限制，请拆成几段发送。") }
        switch textDelivery {
        case .ready: return liveTextStatus == .unsupported ? liveTextDescription : String(localized: "先点电脑里的输入框，再发送整段文字。")
        case .sending: return String(localized: "等待电脑确认… 请勿重复发送。")
        case .sent: return String(localized: "已向电脑系统提交文字；请在屏幕上确认内容。")
        case .rejected(let error): return String(localized: "未被电脑接受：\(error)")
        case .uncertain: return String(localized: "发送结果不完整或未确认，文字可能已输入。请先查看电脑屏幕，避免重复。")
        }
    }

    func acceptPairing(_ raw: String) {
        do {
            let newPairing = try Pairing.parse(raw)
            try PairingStore.write(newPairing)
            desktopControlEnabled = true
            rememberManualTarget()
            if let previous = pairing, previous != newPairing { unlock.forget(previous) }
            disconnect(message: String(localized: "已保存新的配对。"))
            pairing = newPairing
            unlock.setPairing(newPairing)
            pairingError = nil
            connect()
        } catch {
            pairingError = error.localizedDescription
        }
    }

    func forgetPairing() {
        disconnect(message: String(localized: "配对已移除。"))
        if let pairing { unlock.forget(pairing) }
        PairingStore.delete()
        pairing = nil
        unlock.setPairing(nil)
    }

    func becameActive() {
        unlock.becameActive()
        foreground = true
        if !demo, pairing != nil, !connected, !connecting { connect() }
    }

    func setDesktopControlEnabled(_ enabled: Bool) {
        guard enabled != desktopControlEnabled else { return }
        if !enabled { disconnect(message: String(localized: "电脑遥控已暂停，当前选择电视。")) }
        desktopControlEnabled = enabled
        rememberManualTarget()
        if enabled { becameActive() }
    }

    private func rememberManualTarget() {
        guard !demo else { return }
#if SOFATAP_CONTROLLER_TESTING
        guard testSend == nil && testLiveSend == nil else { return }
#endif
        UserDefaults.standard.set(desktopControlEnabled ? "computer" : "webos", forKey: "manualRemoteTarget")
    }

    func becameInactive() {
        unlock.becameInactive()
        guard foreground else { return }
        foreground = false
        stopAirMouse()
        if demo { dragging = false; return }
        disconnect(message: String(localized: "切回 App 会重新连接；草稿已留在手机上。"))
    }

    // A system permission sheet makes the app inactive without backgrounding it.
    // Pause all input but preserve the connection and explicit permission request.
    func pauseInput() {
        stopAirMouse()
        queuedDX = 0; queuedDY = 0; queuedScroll = 0
        setDragging(false)
    }

    func connect() {
        guard desktopControlEnabled, !demo, foreground, !connecting, !connected,
              let pairing, let endpoint = pairing.endpoint else { return }
        generation = UUID()
        let currentGeneration = generation
        connecting = true
        inputAvailable = false
        receiverState = ReceiverState()
        notice = String(localized: "正在验证电脑证书与配对凭据…")
        let delegate = PinnedSessionDelegate(pairing: pairing)
        sessionDelegate = delegate
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 0
        configuration.waitsForConnectivity = true
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let newSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session = newSession
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        let task = newSession.webSocketTask(with: request)
        socket = task
        task.maximumMessageSize = 65_536
        task.resume()
        receiveNext(task, generation: currentGeneration)
        helloTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.generation == currentGeneration, !self.connected else { return }
            self.disconnect(message: String(localized: "连接超时。请检查电脑接收器、家庭网络与本地网络权限。"))
        }
    }

    func disconnect(message: String = String(localized: "已断开连接。")) {
        invalidateLiveText(pause: liveTextSession != nil || liveTextStatus == .starting)
        stopAirMouse()
        motionTimer?.invalidate()
        motionTimer = nil
        keepAliveTask?.cancel()
        keepAliveTask = nil
        helloTimeout?.cancel()
        helloTimeout = nil
        // Best effort release before closing; the receiver independently releases on close/idle.
        if dragging || dragReleasePending, let socket {
            let release: [String: Any] = ["id": UUID().uuidString, "type": "button", "button": "left", "down": false]
            if let data = try? JSONSerialization.data(withJSONObject: release), let text = String(data: data, encoding: .utf8) {
                socket.send(.string(text)) { _ in }
            }
        }
        dragging = false
        dragReleasePending = false
        dragTail = nil
        generation = UUID()
        let oldSocket = socket
        let oldSession = session
        socket = nil
        session = nil
        sessionDelegate = nil
        connected = false
        connecting = false
        inputAvailable = false
        receiverState = ReceiverState()
        motionBusy = false
        scrollBusy = false
        queuedDX = 0; queuedDY = 0; queuedScroll = 0
        let oldPending = pending.values
        pending.removeAll()
        oldPending.forEach { item in item.timer.cancel(); item.completion?(.uncertain) }
        oldSocket?.cancel(with: .goingAway, reason: nil)
        oldSession?.invalidateAndCancel()
        if !demo { notice = message }
    }

    private func receiveNext(_ task: URLSessionWebSocketTask, generation currentGeneration: UUID) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                switch result {
                case .failure:
                    let diagnostic = self.sessionDelegate?.rejectionReason
                    let failureMessage = diagnostic.map { reason in
                        reason == "TLS_VERIFY_-67901"
                        ? String(localized: "电脑证书有效期超出 iOS 限制（\(reason)）。请更新电脑接收器并重新配对。")
                        : String(localized: "电脑证书校验失败（\(reason)）。请检查电脑接收器的证书并重新配对。")
                    }
                    self.disconnect(message: failureMessage ?? String(localized: "连接中断。请检查接收器；未确认的文字不会自动重发。"))
                case .success(let message):
                    let data: Data?
                    switch message {
                    case .string(let value): data = value.data(using: .utf8)
                    case .data(let value): data = value
                    @unknown default: data = nil
                    }
                    guard let data, data.count <= 65_536,
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          self.handle(object) else {
                        self.disconnect(message: String(localized: "接收器协议不匹配，请更新手机和电脑两端。"))
                        return
                    }
                    self.receiveNext(task, generation: currentGeneration)
                }
            }
        }
    }

    private func handle(_ message: [String: Any]) -> Bool {
        switch message["type"] as? String {
        case "hello":
            guard connecting, let version = message["version"] as? Int, version == 1,
                  let name = message["name"] as? String, name.utf8.count <= 256,
                  message["inputAvailable"] is Bool,
                  let state = ReceiverState.hello(message) else { return false }
            helloTimeout?.cancel()
            helloTimeout = nil
            connecting = false
            connected = true
            receiverState = state
            inputAvailable = state.inputAvailable
            computerName = name
            // The retired account-password capability is deliberately ignored.
            // Windows Hello PIN support requires a separate verified protocol.
            notice = state.inputAvailable ? String(localized: "已连接。先点选电脑上的输入框，即可发送文字。") : state.unavailableMessage
            startTimers()
            return true
        case "ack":
            guard connected, let id = message["id"] as? String, let ok = message["ok"] as? Bool else { return false }
            guard let item = pending.removeValue(forKey: id) else { return true }
            item.timer.cancel()
            if item.type == "ping", let state = receiverState.updating(message), state != receiverState {
                let availabilityChanged = state.inputAvailable != receiverState.inputAvailable || state.status != receiverState.status
                updateReceiverState(state)
                if !inputAvailable {
                    stopAirMouse()
                    if dragging { setDragging(false) }
                }
                if availabilityChanged { notice = inputAvailable ? String(localized: "电脑已就绪，可以继续控制。") : state.unavailableMessage }
            }
            if ok { item.completion?(.accepted(message)) }
            else {
                // Show a bounded generic code, not server-controlled arbitrary text or echoed drafts.
                let rawCode = (message["error"] as? String)?.split(separator: ":", maxSplits: 1).first.map(String.init)
                let code = rawCode.flatMap { value -> String? in
                    let allowed = ["input_unavailable", "invalid_frame", "input_failed", "unsupported_key", "too_large", "invalid_message", "rate_limited", "live_text_unsupported", "live_text_conflict", "live_text_changed", "live_text_uncertain", "live_text_invalid"]
                    return allowed.contains(value) ? value : nil
                } ?? String(localized: "操作未完成")
                // A failed injection can have typed a prefix. Unknown errors are conservative.
                let definitelyRejected = ["input_unavailable", "invalid_frame", "input_failed", "unsupported_key", "too_large", "invalid_message", "rate_limited", "live_text_unsupported", "live_text_conflict", "live_text_changed", "live_text_uncertain", "live_text_invalid"].contains(rawCode ?? "")
                if item.type == "text" && !definitelyRejected {
                    notice = String(localized: "电脑未完整确认操作，文字可能已经部分输入。请先查看电脑屏幕。")
                    item.completion?(.uncertain)
                } else {
                    notice = String(localized: "电脑未接受操作：\(code)")
                    item.completion?(.rejected(code))
                }
            }
            return true
        default: return false
        }
    }

    private func startTimers() {
        let currentGeneration = generation
        let timer = Timer(timeInterval: 1.0 / 45.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flushMovement() }
        }
        motionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                // New receivers report only an editable-state hint, never field contents.
                let interval = self?.receiverState.reportsTextFocus == true ? 0.75 : 5.0
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self, self.generation == currentGeneration, self.foreground else { return }
                guard !self.pending.values.contains(where: { $0.type == "ping" }) else { continue }
                self.send("ping", fields: [:], timeout: 8) { result in
                    if case .uncertain = result { self.disconnect(message: String(localized: "电脑没有响应，已停止控制。")) }
                }
            }
        }
    }

    private func send(_ type: String, fields: [String: Any], timeout: Double = 8,
                      completion: ((CommandResult) -> Void)? = nil) {
#if SOFATAP_CONTROLLER_TESTING
        if let testLiveSend {
            guard connected else { completion?(.uncertain); return }
            testLiveSend(type, fields) { reply in
                completion?(reply["ok"] as? Bool == true ? .accepted(reply) : .rejected(reply["error"] as? String ?? "live_text_uncertain"))
            }
            return
        }
        if let testSend {
            guard connected else { completion?(.rejected(String(localized: "尚未连接"))); return }
            testSend(type, fields) { completion?($0 ? .accepted([:]) : .rejected("test_rejected")) }
            return
        }
#endif
        guard connected, let socket else { completion?(.rejected(String(localized: "尚未连接"))); return }
        guard pending.count < 32 else { completion?(.rejected(String(localized: "操作过快，请稍后"))); return }
        let id = UUID().uuidString
        var frame = fields
        frame["type"] = type
        frame["id"] = id
        guard let data = try? JSONSerialization.data(withJSONObject: frame), data.count <= 65_536,
              let text = String(data: data, encoding: .utf8) else {
            completion?(.rejected(String(localized: "文字编码后超过传输限制，请拆成几段"))); return
        }
        let currentGeneration = generation
        let timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self, self.generation == currentGeneration,
                  let item = self.pending.removeValue(forKey: id) else { return }
            item.completion?(.uncertain)
            self.disconnect(message: String(localized: "电脑响应超时，已停止控制。文字可能已输入，请查看电脑屏幕。"))
        }
        pending[id] = Pending(type: type, timer: timer, completion: completion)
        socket.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                self.disconnect(message: String(localized: "发送时连接中断。未确认的文字不会自动重发。"))
            }
        }
    }

    func move(dx: Double, dy: Double) {
        guard canControl, dx.isFinite, dy.isFinite else { return }
        if demo { return }
        // Keep only a small fresh movement window; there is never an unbounded gesture queue.
        if Date().timeIntervalSince(lastMovement) > 0.12 { queuedDX = 0; queuedDY = 0 }
        // While an ACK is outstanding retain the latest sample, not a delayed cursor jump.
        queuedDX = max(-500, min(500, (motionBusy ? 0 : queuedDX) + dx * sensitivity))
        queuedDY = max(-500, min(500, (motionBusy ? 0 : queuedDY) + dy * sensitivity))
        lastMovement = Date()
    }

    func scroll(dy: Double) {
        guard canControl, dy.isFinite else { return }
        if demo { return }
        queuedScroll = max(-1200, min(1200, (scrollBusy ? 0 : queuedScroll) + dy * 8))
        lastScroll = Date()
    }

    private func flushMovement() {
        guard canControl else { queuedDX = 0; queuedDY = 0; queuedScroll = 0; return }
        if !motionBusy, abs(queuedDX) + abs(queuedDY) > 0.01 {
            let dx = queuedDX, dy = queuedDY
            queuedDX = 0; queuedDY = 0
            if Date().timeIntervalSince(lastMovement) <= 0.12 {
                motionBusy = true
                let currentGeneration = generation
                send("move", fields: ["dx": dx, "dy": dy], timeout: 4) { [weak self] result in
                    guard let self, self.generation == currentGeneration else { return }
                    self.motionBusy = false
                    guard self.dragReleasePending else { return }
                    if case .accepted = result { self.finishDragRelease() }
                    else { self.disconnect(message: String(localized: "拖拽移动未得到确认，已断开并释放鼠标。")) }
                }
            }
        }
        if !scrollBusy, abs(queuedScroll) > 0.01 {
            let dy = queuedScroll
            queuedScroll = 0
            if Date().timeIntervalSince(lastScroll) <= 0.12 {
                scrollBusy = true
                send("scroll", fields: ["dx": 0, "dy": dy], timeout: 4) { [weak self] _ in self?.scrollBusy = false }
            }
        }
    }

    func click(_ button: String) {
        guard canControl else { return }
        endLiveTextEditing()
        feedback()
        if demo { notice = button == "left" ? String(localized: "演示：左键单击。") : String(localized: "演示：右键单击。"); return }
        send("click", fields: ["button": button])
    }

    func setDragging(_ down: Bool) {
        guard down != dragging, !down || canControl else { return }
        if down { endLiveTextEditing() }
        dragging = down
        feedback()
        if demo { notice = down ? String(localized: "演示：按住拖拽，再用触控板移动。") : String(localized: "演示：已松开拖拽。"); return }
        if !down {
            // Freeze this gesture's tail before the next run-loop tick or UI
            // cancellation can clear it. It belongs before mouse-up even if an
            // earlier move is still awaiting its ACK or the sample ages out.
            dragTail = abs(queuedDX) + abs(queuedDY) > 0.01 ? (queuedDX, queuedDY) : nil
            queuedDX = 0; queuedDY = 0
            dragReleasePending = true
            finishDragRelease()
            return
        }
        let currentGeneration = generation
        send("button", fields: ["button": "left", "down": true]) { [weak self] result in
            guard let self, self.generation == currentGeneration else { return }
            if case .accepted = result { return }
            self.disconnect(message: String(localized: "拖拽状态未得到确认，已断开并释放鼠标。"))
        }
    }

    private func finishDragRelease() {
        guard dragReleasePending, !motionBusy else { return }
        let currentGeneration = generation
        if let tail = dragTail {
            dragTail = nil
            motionBusy = true
            send("move", fields: ["dx": tail.dx, "dy": tail.dy], timeout: 4) { [weak self] result in
                guard let self, self.generation == currentGeneration else { return }
                self.motionBusy = false
                if case .accepted = result { self.finishDragRelease() }
                else { self.disconnect(message: String(localized: "拖拽移动未得到确认，已断开并释放鼠标。")) }
            }
        } else {
            send("button", fields: ["button": "left", "down": false]) { [weak self] result in
                guard let self, self.generation == currentGeneration else { return }
                if case .accepted = result { self.dragReleasePending = false }
                else { self.disconnect(message: String(localized: "拖拽状态未得到确认，已断开并释放鼠标。")) }
            }
        }
    }

    func key(_ key: String, modifiers: [String] = []) {
        guard canControl else { return }
        endLiveTextEditing()
        feedback()
        if demo { notice = String(localized: "演示：\(key.uppercased()) 快捷键。"); return }
        send("key", fields: ["key": key, "modifiers": modifiers])
    }

    func selectAll() {
        guard !composing else { return }
        if liveTextReady { editText(draft, selection: NSRange(location: 0, length: draft.utf16.count), marked: false) }
        else { key("a", modifiers: [receiverState.commandModifier]) }
    }

    func sendText() {
        guard canSendText else { return }
        feedback()
        sentSnapshot = draft
        if demo {
            lastSentDraft = draft
            textDelivery = .sent
            notice = String(localized: "演示：没有将文字发送到任何电脑。")
            return
        }
        textDelivery = .sending
        send("text", fields: ["text": sentSnapshot]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .accepted:
                self.lastSentDraft = self.sentSnapshot
                self.textDelivery = self.draft == self.sentSnapshot ? .sent : .ready
            case .rejected(let error): self.textDelivery = .rejected(error)
            case .uncertain: self.textDelivery = .uncertain
            }
        }
    }

    func allowManualResend() {
        guard !sendingText else { return }
        textDelivery = .ready
        lastSentDraft = nil
    }

    func clearDraft() {
        guard !sendingText else { return }
        if liveTextReady { editText("", selection: NSRange(location: 0, length: 0), marked: false) }
        else { draft = ""; draftSelection = NSRange(location: 0, length: 0) }
        textDelivery = .ready
        lastSentDraft = nil
    }

    /// Opening is an explicit or editable-focus-triggered snapshot request. The
    /// editor stays disabled until its initial snapshot has been acknowledged.
    func openTextEditor(completion: (() -> Void)? = nil) {
        guard canControl, remoteTextFocus != .protected else { return }
        guard usesLiveText else { completion?(); return }
        if liveTextPaused { return }
        if liveTextReady { completion?(); return }
        if let completion { liveTextOpenCallbacks.append(completion) }
        if liveTextStatus == .starting { return }
        liveTextOpeningSnapshot = LiveTextSnapshot(text: draft, selection: draftSelection)
        liveTextStatus = .starting
        let epoch = UUID(); liveTextEpoch = epoch
        send("textBegin", fields: [:]) { [weak self] result in
            guard let self, self.liveTextEpoch == epoch else { return }
            switch result {
            case .accepted(let message):
                guard let reply = message["liveText"] as? [String: Any],
                      let session = reply["session"] as? String, UUID(uuidString: session) != nil,
                      LiveTextSnapshot.integer(reply["revision"]) == 0,
                      let snapshot = LiveTextSnapshot.parse(reply) else { self.pauseLiveText("live_text_uncertain"); return }
                self.liveTextSession = session; self.liveTextRevision = 0
                self.liveTextBaseline = snapshot; self.liveTextDesired = snapshot
                self.ephemeralDraft = true
                self.applyLiveSnapshot(snapshot)
                self.liveTextStatus = .active
                let callbacks = self.liveTextOpenCallbacks; self.liveTextOpenCallbacks.removeAll()
                callbacks.forEach { $0() }
            case .rejected(let code) where code == "live_text_unsupported":
                self.liveTextStatus = .unsupported
                // A previous imported field must never become an append-only
                // fallback draft which would duplicate that field on Send.
                if self.ephemeralDraft { self.draft = ""; self.draftSelection = NSRange(location: 0, length: 0) }
                self.ephemeralDraft = false
                self.textDelivery = .ready
                self.lastSentDraft = nil
                let callbacks = self.liveTextOpenCallbacks; self.liveTextOpenCallbacks.removeAll()
                callbacks.forEach { $0() }
            case .rejected(let code): self.pauseLiveText(code)
            case .uncertain: self.pauseLiveText("live_text_uncertain")
            }
        }
    }

    func restartLiveTextEditing() {
        guard usesLiveText, canControl else { return }
        // User explicitly asks to replace the retained draft with a new snapshot.
        invalidateLiveText(pause: false)
        liveTextStatus = .idle
        openTextEditor()
    }

    func editText(_ text: String, selection: NSRange, marked: Bool) {
        draft = text; draftSelection = selection; composing = marked
        let desired = LiveTextSnapshot(text: text, selection: selection)
        if liveTextStatus == .starting && (desired != liveTextOpeningSnapshot || marked) {
            // A final native callback may race with the render which disables
            // the editor. Preserve that edit rather than importing over it.
            pauseLiveText("live_text_changed")
            return
        }
        guard liveTextReady else { return }
        liveTextDesired = desired
        guard !marked else { return } // IME's provisional Latin syllables stay local.
        guard desired.valid else { pauseLiveText("live_text_invalid"); return }
        flushLiveText()
    }

    private func flushLiveText() {
        guard liveTextStatus == .active, !composing,
              let session = liveTextSession, let desired = liveTextDesired,
              desired.valid, desired != liveTextBaseline else { return }
        let epoch = liveTextEpoch, revision = liveTextRevision + 1
        var fields = desired.fields; fields["session"] = session; fields["revision"] = revision
        liveTextStatus = .syncing
        send("textSync", fields: fields) { [weak self] result in
            guard let self, self.liveTextEpoch == epoch else { return }
            switch result {
            case .accepted(let message):
                guard let reply = message["liveText"] as? [String: Any],
                      reply["session"] as? String == session,
                      LiveTextSnapshot.integer(reply["revision"]) == revision,
                      let canonical = LiveTextSnapshot.parse(reply) else { self.pauseLiveText("live_text_uncertain"); return }
                self.liveTextBaseline = canonical; self.liveTextRevision = revision
                self.liveTextStatus = .active
                if self.liveTextDesired == desired && !self.composing {
                    self.liveTextDesired = canonical
                    self.applyLiveSnapshot(canonical)
                }
                self.flushLiveText()
            case .rejected(let code): self.pauseLiveText(code)
            case .uncertain: self.pauseLiveText("live_text_uncertain")
            }
        }
    }

    private func applyLiveSnapshot(_ snapshot: LiveTextSnapshot) {
        draft = snapshot.text; draftSelection = snapshot.selection
    }
    private func pauseLiveText(_ code: String) {
        invalidateLiveText(pause: true)
        liveTextStatus = .paused(code)
        notice = String(localized: "实时编辑已暂停。请检查电脑输入框；手机上的文字不会自动重发。")
    }
    func endLiveTextEditing() {
        guard liveTextSession != nil || liveTextStatus == .starting else { return }
        let unsynchronized = liveTextStatus == .syncing || composing || liveTextDesired != liveTextBaseline
        invalidateLiveText(pause: unsynchronized)
    }
    private func invalidateLiveText(pause: Bool) {
        let session = liveTextSession
        liveTextEpoch = UUID(); liveTextSession = nil; liveTextBaseline = nil; liveTextDesired = nil; liveTextOpeningSnapshot = nil
        liveTextOpenCallbacks.removeAll()
        if pause { liveTextStatus = .paused("live_text_changed") }
        else if !liveTextPaused { liveTextStatus = .idle }
        if let session, connected { send("textEnd", fields: ["session": session]) }
    }
    private func updateReceiverState(_ state: ReceiverState) {
        if state.focusRevision != receiverState.focusRevision || !state.inputAvailable || state.textFocus == .protected {
            endLiveTextEditing()
            if liveTextStatus == .unsupported { liveTextStatus = .idle }
        }
        receiverState = state; inputAvailable = state.inputAvailable
    }

    func startAirMouse() {
        guard canControl, foreground, !airMoving else { return }
        if demo { airMoving = true; feedback(); return }
        guard motion.isDeviceMotionAvailable else { notice = String(localized: "这台设备没有可用的陀螺仪，请使用触控板。"); return }
        airMoving = true
        feedback()
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, error in
            Task { @MainActor in
                guard let self, self.airMoving else { return }
                if error != nil {
                    self.stopAirMouse()
                    self.notice = String(localized: "无法读取陀螺仪，请检查运动权限或使用触控板。")
                    return
                }
                guard let data, ProcessInfo.processInfo.systemUptime - data.timestamp <= 0.15 else { return }
                // Portrait, screen facing the user: y is left/right yaw, x is up/down pitch.
                let yaw = abs(data.rotationRate.y) < 0.015 ? 0 : data.rotationRate.y
                let pitch = abs(data.rotationRate.x) < 0.015 ? 0 : data.rotationRate.x
                self.move(dx: -yaw * 18, dy: -pitch * 18)
            }
        }
    }

    func stopAirMouse() {
        motion.stopDeviceMotionUpdates()
        airMoving = false
        queuedDX = 0; queuedDY = 0
    }

    private func feedback() {
#if SOFATAP_CONTROLLER_TESTING
        if testSend != nil || testLiveSend != nil { return }
#endif
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func persistDeliveryState() {
#if SOFATAP_CONTROLLER_TESTING
        if testSend != nil || testLiveSend != nil { return }
#endif
        guard !demo else { return }
        switch textDelivery {
        case .sending:
            UserDefaults.standard.set(digest(sentSnapshot), forKey: "sentDraftDigest")
            UserDefaults.standard.set("pending", forKey: "textDeliveryMarker")
        case .sent:
            UserDefaults.standard.set(digest(lastSentDraft ?? sentSnapshot), forKey: "sentDraftDigest")
            UserDefaults.standard.set("sent", forKey: "textDeliveryMarker")
        case .uncertain:
            UserDefaults.standard.set("uncertain", forKey: "textDeliveryMarker")
        case .ready, .rejected:
            UserDefaults.standard.removeObject(forKey: "textDeliveryMarker")
            UserDefaults.standard.removeObject(forKey: "sentDraftDigest")
        }
    }
}
