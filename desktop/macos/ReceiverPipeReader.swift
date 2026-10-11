import Darwin
import Dispatch
import Foundation

enum ReceiverPipeEvent: Sendable {
    case state(ReceiverState)
    case ended
}

/// Each pipe has its own readiness source. FileHandle.bytes shares a serial Foundation IO actor,
/// so a quiet stderr can otherwise block the stdout reader indefinitely.
final class ReceiverPipeReader: @unchecked Sendable {
    let events: AsyncStream<ReceiverPipeEvent>
    private let continuation: AsyncStream<ReceiverPipeEvent>.Continuation
    private let source: DispatchSourceRead
    private let descriptor: Int32
    private let parsesStates: Bool
    // Accessed only by this reader's serial dispatch queue.
    private var lineBuffer = ReceiverLineBuffer()

    init(handle: FileHandle, parsesStates: Bool) throws {
        let descriptor = dup(handle.fileDescriptor)
        guard descriptor >= 0 else { throw POSIXError(.EBADF) }
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            close(descriptor)
            throw POSIXError(.EIO)
        }
        self.descriptor = descriptor
        self.parsesStates = parsesStates
        let (events, continuation) = AsyncStream<ReceiverPipeEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.events = events
        self.continuation = continuation
        self.source = DispatchSource.makeReadSource(fileDescriptor: descriptor,
            queue: DispatchQueue(label: parsesStates ? "sofatap.stdout" : "sofatap.stderr"))
        source.setEventHandler { [weak self] in self?.readAvailable() }
        // Dispatch closes only this duplicate, after any executing event handler finishes.
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    func cancel() {
        source.cancel()
        continuation.finish()
    }

    private func readAvailable() {
        var bytes = [UInt8](repeating: 0, count: 16_384)
        // Bound a single handler turn; level-triggered readiness schedules the next one if needed.
        for _ in 0..<32 {
            let count = read(descriptor, &bytes, bytes.count)
            if count > 0 {
                if parsesStates {
                    do {
                        for byte in bytes.prefix(count) {
                            if let frame = try lineBuffer.append(byte) {
                                continuation.yield(.state(try ReceiverState.decode(frame)))
                            }
                        }
                    } catch { end(); return }
                }
                // stderr is drained and discarded without decoding, logging, or displaying it.
            } else if count == 0 { end(); return }
            else if errno == EINTR { continue }
            else if errno == EAGAIN || errno == EWOULDBLOCK { return }
            else { end(); return }
        }
    }

    private func end() {
        continuation.yield(.ended)
        continuation.finish()
        source.cancel()
    }

    deinit { source.cancel(); continuation.finish() }
}
