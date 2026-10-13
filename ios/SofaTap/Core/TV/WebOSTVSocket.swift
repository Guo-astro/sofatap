import Foundation
import Security
import CryptoKit

/// The network boundary is injectable; protocol/lifecycle tests never contact a TV.
@MainActor
protocol WebOSTVSocket: AnyObject {
    var onOpen: (() -> Void)? { get set }
    var onText: ((String) -> Void)? { get set }
    var onFailure: (() -> Void)? { get set }
    var onCertificate: ((String) -> Void)? { get set }
    func open(_ url: URL, fingerprint: String?)
    func send(_ text: String, completion: @escaping (Bool) -> Void)
    func ping(completion: @escaping (Bool) -> Void)
    func close()
}

@MainActor
final class WebOSTVNetworkSocket: WebOSTVSocket {
    var onOpen: (() -> Void)?
    var onText: ((String) -> Void)?
    var onFailure: (() -> Void)?
    var onCertificate: ((String) -> Void)?
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var delegate: WebOSTVSocketDelegate?
    private var epoch = UUID()
    private var reportedFailure = false

    func open(_ url: URL, fingerprint: String?) {
        close()
        let current = epoch
        reportedFailure = false
        let delegate = WebOSTVSocketDelegate(host: url.host ?? "", port: url.port ?? 3001,
                                            fingerprint: fingerprint)
        delegate.opened = { [weak self] in
            Task { @MainActor in
                guard let self, self.epoch == current else { return }
                self.onOpen?()
            }
        }
        delegate.failed = { [weak self] in
            Task { @MainActor in self?.fail(current) }
        }
        self.delegate = delegate
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 0
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 65_536
        self.task = task
        task.resume()
        receive(task, current)
    }

    private func receive(_ socket: URLSessionWebSocketTask, _ current: UUID) {
        socket.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.epoch == current else { return }
                switch result {
                case .success(.string(let text)):
                    guard text.utf8.count <= 65_536 else { self.fail(current); return }
                    self.onText?(text)
                    if self.epoch == current { self.receive(socket, current) }
                case .success(.data): self.fail(current)
                case .failure: self.fail(current)
                @unknown default: self.fail(current)
                }
            }
        }
    }

    private func fail(_ current: UUID) {
        guard epoch == current, !reportedFailure else { return }
        reportedFailure = true
        // An inspection handshake deliberately rejects TLS. Its captured leaf is
        // presented for explicit local trust; no SSAP credential has been sent.
        if let pin = delegate?.inspectedFingerprint { onCertificate?(pin) }
        else { onFailure?() }
    }

    func send(_ text: String, completion: @escaping (Bool) -> Void) {
        guard let task else { completion(false); return }
        let current = epoch
        task.send(.string(text)) { [weak self] error in
            Task { @MainActor in
                guard let self, self.epoch == current else { return }
                completion(error == nil)
            }
        }
    }

    func ping(completion: @escaping (Bool) -> Void) {
        guard let task else { completion(false); return }
        let current = epoch
        task.sendPing { [weak self] error in
            Task { @MainActor in
                guard let self, self.epoch == current else { return }
                completion(error == nil)
            }
        }
    }

    func close() {
        epoch = UUID()
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        task = nil; session = nil; delegate = nil
    }
}

private final class WebOSTVSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    let host: String
    let port: Int
    let fingerprint: String?
    var opened: (() -> Void)?
    var failed: (() -> Void)?
    private let lock = NSLock()
    private var observed: String?
    var inspectedFingerprint: String? {
        lock.lock(); defer { lock.unlock() }
        return fingerprint == nil ? observed : nil
    }
    init(host: String, port: Int, fingerprint: String?) {
        self.host = host; self.port = port; self.fingerprint = fingerprint
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host, challenge.protectionSpace.port == port,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let pin = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        guard let fingerprint else {
            lock.lock(); observed = pin; lock.unlock()
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        guard pin == fingerprint else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        // webOS uses a self-signed TV certificate that may not name its private IP.
        // The exact leaf was explicitly trusted in-app, then bound to the approved
        // TV pairing. Never install a CA, broaden trust, follow redirects or use ws.
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) { opened?() }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) { failed?() }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil { failed?() }
    }
}
