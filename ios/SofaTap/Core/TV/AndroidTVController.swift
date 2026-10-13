import Foundation
import Combine

/// The free Android receiver adapter. It sends only explicit manual input and never replays it.
@MainActor
final class AndroidTVController: ObservableObject {
    enum Phase: Equatable { case idle, connecting, ready, failed }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var saved: AndroidTVPairing?
    @Published private(set) var name = ""
    @Published private(set) var status: AndroidTVStatus?
    @Published private(set) var notice = String(localized: "扫描 Android TV 接收器中的二维码。")
    @Published private var paused = false
    var busy: Bool { phase == .connecting }
    var canControl: Bool { phase == .ready && !paused && status?.available == true }
    var title: String {
        switch phase {
        case .idle, .failed: String(localized: "Android TV 未连接")
        case .connecting: String(localized: "正在连接 Android TV…")
        case .ready: status?.available == true ? String(localized: "Android TV · 实验性遥控") : String(localized: "Android TV · 等待权限")
        }
    }
    private let enabled: Bool
    private let storage: AndroidTVPairingStorage
    private let makeSocket: @MainActor () -> AndroidTVSocket
    private var socket: AndroidTVSocket?
    private var pairing: AndroidTVPairing?
    private var bootstrap = false
    private var epoch = UUID()
    private var deadline: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private struct Input { let action: AndroidTVAction; let time: TimeInterval }
    private var queue: [Input] = []
    private var pending: (id: String, action: AndroidTVAction)?

    init(enabled: Bool = true, storage: AndroidTVPairingStorage = AndroidTVKeychain(),
         makeSocket: @escaping @MainActor () -> AndroidTVSocket = { AndroidTVNetworkSocket() }) {
        self.enabled = enabled; self.storage = storage; self.makeSocket = makeSocket
        saved = enabled ? storage.read() : nil
    }

    func pair(_ raw: String) {
        guard enabled else { return }
        guard let pairing = try? AndroidTVPairing.parse(raw) else {
            fail(String(localized: "Android TV 配对二维码无效，请在电视上生成新的二维码。")); return
        }
        connect(pairing, bootstrap: true)
    }
    func reconnect() {
        guard enabled, let saved else { return }
        connect(saved, bootstrap: false)
    }
    private func connect(_ pairing: AndroidTVPairing, bootstrap: Bool) {
        disconnect()
        self.pairing = pairing; self.bootstrap = bootstrap
        phase = .connecting
        notice = String(localized: "正在验证电视加密连接…")
        let current = epoch
        let socket = makeSocket(); self.socket = socket
        socket.onFailure = { [weak self] in self?.failIfCurrent(current) }
        socket.onText = { [weak self] text in
            guard let self, self.epoch == current else { return }
            self.receive(text)
        }
        armDeadline(seconds: 12)
        socket.open(pairing)
    }
    private func receive(_ text: String) {
        do {
            switch try AndroidTVProtocol.parse(text) {
            case .hello(let name, let status, let token):
                guard phase == .connecting, let pairing,
                      bootstrap ? token != nil : token == nil else { throw AndroidTVError.malformedMessage }
                if let token {
                    // The five-minute QR token is never persisted or retried.
                    let resumed = pairing.replacingToken(token)
                    try storage.write(resumed)
                    saved = resumed; self.pairing = resumed
                }
                deadline?.cancel(); deadline = nil
                self.name = name; self.status = status; phase = .ready
                updateNotice()
                startHeartbeat()
            case .ack(let id, let ok, let newStatus, _):
                guard phase == .ready, let pending, pending.id == id else { throw AndroidTVError.malformedMessage }
                if pending.action == .ping, newStatus == nil { throw AndroidTVError.malformedMessage }
                deadline?.cancel(); deadline = nil; self.pending = nil
                if let newStatus {
                    status = newStatus
                    if !newStatus.available { queue.removeAll() }
                }
                if ok { updateNotice() }
                else {
                    queue.removeAll()
                    notice = String(localized: "电视未接受这次操作。请查看电视；此应用或控件可能不支持遥控。")
                }
                drain()
            }
        } catch { fail(String(localized: "电视连接或配对未确认。请在电视上生成新二维码后重新连接。")) }
    }
    private func updateNotice() {
        switch status?.inputStatus {
        case .ready:
            notice = String(localized: "实验性控制：移动屏幕上的指示光标，点击可访问控件。操作结果请以电视画面为准。")
        case .accessibilityRequired:
            notice = String(localized: "已连接。请在电视设置中启用 Sofatap 辅助功能服务，然后返回接收器。")
        case .screenLocked:
            notice = String(localized: "电视当前已锁定，请先使用电视遥控器解锁。")
        case .unavailable, nil:
            notice = String(localized: "电视输入当前不可用，请查看接收器中的权限与兼容性提示。")
        }
    }
    func move(dx: Double, dy: Double) {
        guard status?.capabilities.overlayCursor == true else { return }
        enqueue(.move(dx: dx, dy: dy))
    }
    func click() {
        guard status?.capabilities.nodeClick == true else { return }
        enqueue(.click)
    }
    func scroll(dy: Double) {
        guard status?.capabilities.scroll == true else { return }
        // Phone gestures emit desktop wheel deltas: negative scrolls the document down.
        // Android's accessible-container action uses a positive delta for document down.
        enqueue(.scroll(dx: 0, dy: -dy))
    }
    func key(_ key: AndroidTVKey) {
        let caps = status?.capabilities
        guard key == .back ? caps?.back == true : key == .home ? caps?.home == true : caps?.directionalFocus == true else { return }
        enqueue(.key(key))
    }
    private func enqueue(_ action: AndroidTVAction) {
        guard canControl, (try? AndroidTVProtocol.encode(action, id: UUID().uuidString)) != nil else { return }
        let now = Date.timeIntervalSinceReferenceDate
        queue.removeAll { now - $0.time > 0.5 }
        // Coalesce adjacent motion only. Never merge movement across a click/key boundary.
        if case .move(let dx, let dy) = action, let last = queue.last, case .move(let x, let y) = last.action {
            let merged = AndroidTVAction.move(dx: max(-500, min(500, dx + x)), dy: max(-500, min(500, dy + y)))
            queue[queue.count - 1] = Input(action: merged, time: now)
        } else {
            guard queue.count < 24 else { fail(String(localized: "电视响应过慢，已停止发送。请查看电视后手动重新连接。")); return }
            queue.append(Input(action: action, time: now))
        }
        drain()
    }
    private func drain() {
        guard phase == .ready, pending == nil, !paused, status?.available == true else { return }
        let now = Date.timeIntervalSinceReferenceDate
        queue.removeAll { now - $0.time > 0.5 }
        guard !queue.isEmpty else { return }
        send(queue.removeFirst().action)
    }
    private func send(_ action: AndroidTVAction) {
        guard phase == .ready, pending == nil else { return }
        let id = UUID().uuidString, current = epoch
        guard let message = try? AndroidTVProtocol.encode(action, id: id) else { return }
        pending = (id, action)
        armDeadline(seconds: 3)
        socket?.send(message) { [weak self] ok in if !ok { self?.failIfCurrent(current) } }
    }
    private func startHeartbeat() {
        let current = epoch
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
                guard let self, self.epoch == current, self.phase == .ready else { return }
                if self.pending == nil { self.send(.ping) }
            }
        }
    }
    private func armDeadline(seconds: UInt64) {
        deadline?.cancel()
        let current = epoch
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            self?.failIfCurrent(current)
        }
    }
    private func failIfCurrent(_ current: UUID) {
        guard epoch == current else { return }
        fail(String(localized: "电视连接中断，未确认的操作不会重发。请查看电视后手动重新连接。"))
    }
    private func fail(_ message: String) { disconnect(); phase = .failed; notice = message }
    func pauseInput() { paused = true; queue.removeAll() }
    func resumeInput() { paused = false }
    func disconnect() {
        epoch = UUID()
        deadline?.cancel(); deadline = nil; heartbeat?.cancel(); heartbeat = nil
        socket?.close(); socket = nil; pairing = nil; pending = nil; queue.removeAll()
        status = nil; phase = .idle; paused = false
        notice = String(localized: "Android TV 已断开。请手动重新连接。")
    }
    func forget() {
        guard enabled else { return }
        disconnect()
        do { try storage.delete(); saved = nil }
        catch { fail(String(localized: "无法移除电视配对，请稍后重试。")) }
    }
}
