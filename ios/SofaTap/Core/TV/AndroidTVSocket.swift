import Foundation

@MainActor
protocol AndroidTVSocket: AnyObject {
    var onText: ((String) -> Void)? { get set }
    var onFailure: (() -> Void)? { get set }
    func open(_ pairing: AndroidTVPairing)
    func send(_ text: String, completion: @escaping (Bool) -> Void)
    func close()
}

/// The QR pins the exact host, port and leaf certificate before the bearer header is sent.
@MainActor
final class AndroidTVNetworkSocket: AndroidTVSocket {
    var onText: ((String) -> Void)?
    var onFailure: (() -> Void)?
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var epoch = UUID()
    private var reportedFailure = false
    func open(_ pairing: AndroidTVPairing) {
        close()
        guard (try? pairing.validate()) != nil else { onFailure?(); return }
        let current = epoch
        reportedFailure = false
        let delegate = PinnedSessionDelegate(pairing: Pairing(host: pairing.host, port: pairing.port,
                                                             token: pairing.token, fingerprint: pairing.fingerprint))
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 0
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: pairing.endpoint)
        request.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = AndroidTVProtocol.maximumMessageBytes
        self.task = task
        task.resume()
        receive(task, current)
    }
    private func receive(_ task: URLSessionWebSocketTask, _ current: UUID) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.epoch == current else { return }
                switch result {
                case .success(.string(let text)):
                    guard text.utf8.count <= AndroidTVProtocol.maximumMessageBytes else { self.fail(current); return }
                    self.onText?(text)
                    if self.epoch == current { self.receive(task, current) }
                default: self.fail(current)
                }
            }
        }
    }
    private func fail(_ current: UUID) {
        guard epoch == current, !reportedFailure else { return }
        reportedFailure = true
        onFailure?()
    }
    func send(_ text: String, completion: @escaping (Bool) -> Void) {
        guard let task, text.utf8.count <= AndroidTVProtocol.maximumMessageBytes else { completion(false); return }
        let current = epoch
        task.send(.string(text)) { [weak self] error in
            Task { @MainActor in
                guard self?.epoch == current else { return }
                completion(error == nil)
            }
        }
    }
    func close() {
        epoch = UUID()
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        task = nil; session = nil
    }
}
