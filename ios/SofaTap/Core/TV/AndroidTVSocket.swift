import Foundation

enum AndroidTVSocketFailure: Equatable { case transient, permanent }

@MainActor
protocol AndroidTVSocket: AnyObject {
    var onText: ((String) -> Void)? { get set }
    var onFailure: ((AndroidTVSocketFailure) -> Void)? { get set }
    func open(_ pairing: AndroidTVPairing)
    func send(_ text: String, completion: @escaping (Bool) -> Void)
    func close()
}

/// The QR pins the exact host, port and leaf certificate before the bearer header is sent.
@MainActor
final class AndroidTVNetworkSocket: AndroidTVSocket {
    var onText: ((String) -> Void)?
    var onFailure: ((AndroidTVSocketFailure) -> Void)?
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var epoch = UUID()
    private var reportedFailure = false
    private var delegate: PinnedSessionDelegate?
    private var receivedText = false
    func open(_ pairing: AndroidTVPairing) {
        close()
        guard (try? pairing.validate()) != nil else { onFailure?(.permanent); return }
        let current = epoch
        reportedFailure = false; receivedText = false
        let delegate = PinnedSessionDelegate(pairing: Pairing(host: pairing.host, port: pairing.port,
                                                             token: pairing.token, fingerprint: pairing.fingerprint))
        self.delegate = delegate
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
                    guard text.utf8.count <= AndroidTVProtocol.maximumMessageBytes else { self.fail(current, .permanent); return }
                    self.receivedText = true
                    self.onText?(text)
                    if self.epoch == current { self.receive(task, current) }
                case .failure(let error): self.fail(current, self.classify(error, task: task))
                default: self.fail(current, .permanent)
                }
            }
        }
    }
    private func classify(_ error: Error, task: URLSessionWebSocketTask) -> AndroidTVSocketFailure {
        Self.classify(error, diagnostic: delegate?.rejectionReason,
                      status: (task.response as? HTTPURLResponse)?.statusCode,
                      closeCode: task.closeCode, receivedText: receivedText)
    }
    /// TLS/auth/protocol rejection never becomes an automatic retry loop.
    static func classify(_ error: Error, diagnostic: String?, status: Int?,
                         closeCode: URLSessionWebSocketTask.CloseCode = .invalid,
                         receivedText: Bool = false) -> AndroidTVSocketFailure {
        guard diagnostic == nil else { return .permanent }
        if let status, status != 101 {
            if (300...499).contains(status) {
                return [408, 409, 429].contains(status) ? .transient : .permanent
            }
            if (500...599).contains(status) { return .transient }
        }
        switch closeCode {
        case .protocolError, .unsupportedData, .invalidFramePayloadData, .policyViolation, .messageTooBig,
             .mandatoryExtensionMissing, .tlsHandshakeFailure: return .permanent
        default: break
        }
        let failure = error as NSError
        let terminalURLCodes: [URLError.Code] = [.secureConnectionFailed, .serverCertificateHasBadDate,
            .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
            .clientCertificateRejected, .clientCertificateRequired, .userAuthenticationRequired,
            .userCancelledAuthentication, .appTransportSecurityRequiresSecureConnection]
        if failure.domain == NSURLErrorDomain && terminalURLCodes.contains(URLError.Code(rawValue: failure.code)) { return .permanent }
        if receivedText && (closeCode == .normalClosure || closeCode == .goingAway || closeCode == .internalServerError) { return .transient }
        if failure.domain == NSURLErrorDomain {
            return [URLError.Code.timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                    .networkConnectionLost, .notConnectedToInternet, .resourceUnavailable].contains(URLError.Code(rawValue: failure.code)) ? .transient : .permanent
        }
        if failure.domain == NSPOSIXErrorDomain {
            return [ECONNRESET, ECONNREFUSED, ENOTCONN, ETIMEDOUT, ENETDOWN, ENETUNREACH,
                    EHOSTDOWN, EHOSTUNREACH, EPIPE].contains(Int32(failure.code)) ? .transient : .permanent
        }
        return .permanent
    }
    private func fail(_ current: UUID, _ failure: AndroidTVSocketFailure) {
        guard epoch == current, !reportedFailure else { return }
        reportedFailure = true
        onFailure?(failure)
    }
    func send(_ text: String, completion: @escaping (Bool) -> Void) {
        guard let task, text.utf8.count <= AndroidTVProtocol.maximumMessageBytes else { completion(false); return }
        let current = epoch
        task.send(.string(text)) { [weak self] error in
            Task { @MainActor in
                guard let self, self.epoch == current else { return }
                if let error { self.fail(current, self.classify(error, task: task)) }
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
