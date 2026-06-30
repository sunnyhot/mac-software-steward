import Foundation

@main
struct CommandRunnerControlTest {
    static func main() async {
        let timeout = await CommandRunner.runStreamingDetailed(
            "/bin/sleep",
            arguments: ["2"],
            timeout: 0.2,
            cancellationToken: CommandCancellationToken()
        ) { _, _ in }
        precondition(timeout.terminationReason == .timedOut)

        let token = CommandCancellationToken()
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            token.cancel()
        }
        let cancelled = await CommandRunner.runStreamingDetailed(
            "/bin/sleep",
            arguments: ["2"],
            timeout: 5,
            cancellationToken: token
        ) { _, _ in }
        precondition(cancelled.terminationReason == .cancelled)

        let overlayResult = await CommandRunner.run(
            "/bin/sh",
            arguments: ["-c", "printf '%s' \"$MSS_TEST_OVERLAY\""],
            timeout: 5,
            environmentOverlay: ["MSS_TEST_OVERLAY": "works"]
        )
        precondition(overlayResult.ok)
        precondition(overlayResult.stdout == "works")

        let streamingCapture = OutputCapture()
        let streamingOverlay = await CommandRunner.runStreamingDetailed(
            "/bin/sh",
            arguments: ["-c", "printf '%s' \"$MSS_STREAMING_OVERLAY\""],
            timeout: 5,
            environmentOverlay: ["MSS_STREAMING_OVERLAY": "streaming"]
        ) { stream, text in
            streamingCapture.append(stream: stream, text: text)
        }
        precondition(streamingOverlay.code == 0)
        precondition(streamingCapture.text.contains("streaming"))
    }
}

private final class OutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(stream: String, text: String) {
        lock.lock()
        lines.append("[\(stream)] \(text)")
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}
