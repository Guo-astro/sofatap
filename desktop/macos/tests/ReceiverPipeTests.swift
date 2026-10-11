import Foundation

@main
enum ReceiverPipeTests {
    static func main() async throws {
        var checks = 0
        func check(_ value: Bool, _ name: String) { precondition(value, name); checks += 1 }
        func next(_ reader: ReceiverPipeReader) async -> ReceiverPipeEvent? {
            await withTaskGroup(of: ReceiverPipeEvent?.self) { group in
                group.addTask { for await event in reader.events { return event }; return nil }
                group.addTask { try? await Task.sleep(for: .seconds(2)); return nil }
                let result = await group.next() ?? nil
                group.cancelAll()
                return result
            }
        }
        // Hold stderr open without writing anything. Stdout must remain independently readable.
        let stdout = Pipe(), stderr = Pipe()
        let drain = try ReceiverPipeReader(handle: stderr.fileHandleForReading, parsesStates: false)
        let reader = try ReceiverPipeReader(handle: stdout.fileHandleForReading, parsesStates: true)
        defer {
            drain.cancel(); reader.cancel()
            try? stdout.fileHandleForReading.close(); try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForReading.close(); try? stderr.fileHandleForWriting.close()
        }
        let state = Data("{\"type\":\"state\",\"name\":\"Pipe test\",\"platform\":\"macos\",\"inputStatus\":\"dry_run\",\"dryRun\":true,\"connected\":false,\"pairings\":[]}\n".utf8)
        try stdout.fileHandleForWriting.write(contentsOf: state)
        if case .state(let first) = await next(reader) { check(first.name == "Pipe test", "stdout received while stderr is quiet") }
        else { preconditionFailure("quiet stderr blocked stdout") }

        // Sustained stderr output must drain without stealing or corrupting stdout frames.
        let noise = Task.detached { try stderr.fileHandleForWriting.write(contentsOf: Data(repeating: 65, count: 128 * 1_024)) }
        try stdout.fileHandleForWriting.write(contentsOf: state)
        if case .state = await next(reader) { check(true, "stdout received while stderr exceeds pipe capacity") }
        else { preconditionFailure("stderr blocked stdout") }
        try await noise.value
        check(true, "stderr larger than pipe capacity drained")
        try stdout.fileHandleForWriting.close()
        if case .ended = await next(reader) { check(true, "stdout EOF delivered") }
        else { preconditionFailure("stdout EOF not delivered") }

        let invalidPipe = Pipe()
        let invalid = try ReceiverPipeReader(handle: invalidPipe.fileHandleForReading, parsesStates: true)
        defer { invalid.cancel(); try? invalidPipe.fileHandleForReading.close(); try? invalidPipe.fileHandleForWriting.close() }
        try invalidPipe.fileHandleForWriting.write(contentsOf: Data("not JSON\n".utf8))
        if case .ended = await next(invalid) { check(true, "invalid frame ends state stream") }
        else { preconditionFailure("invalid frame was accepted") }
        print("PASS: \(checks) native pipe integration checks (no app, backend, network, or input)")
    }
}
