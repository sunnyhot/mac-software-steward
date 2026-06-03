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
    }
}
