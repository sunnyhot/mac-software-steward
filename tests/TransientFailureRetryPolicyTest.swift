import Foundation

@main
struct TransientFailureRetryPolicyTest {
    static func main() {
        for output in [
            "Error: Download failed for cask",
            "curl error: Couldn't resolve host",
            "HTTP error 503 Service Unavailable",
            "connection reset by peer",
            "Operation timed out"
        ] {
            precondition(TransientFailureRetryPolicy.shouldRetry(code: 1, output: output, terminationReason: .exited, retryAttempt: 0), output)
            precondition(TransientFailureRetryPolicy.shouldRetry(code: 1, output: output, terminationReason: .exited, retryAttempt: 1), output)
            precondition(!TransientFailureRetryPolicy.shouldRetry(code: 1, output: output, terminationReason: .exited, retryAttempt: 2), output)
        }

        for output in [
            "Download failed: Permission denied",
            "Download failed: checksum mismatch",
            "sudo: a password is required",
            "syntax error: unexpected identifier",
            "Error: App already exists",
            "HTTP error 404: Not Found"
        ] {
            precondition(!TransientFailureRetryPolicy.shouldRetry(code: 1, output: output, terminationReason: .exited, retryAttempt: 0), output)
        }

        precondition(!TransientFailureRetryPolicy.shouldRetry(code: 0, output: "ok", terminationReason: .exited, retryAttempt: 0))
        precondition(!TransientFailureRetryPolicy.shouldRetry(code: 1, output: "Download failed", terminationReason: .cancelled, retryAttempt: 0))
        precondition(!TransientFailureRetryPolicy.shouldRetry(code: 1, output: "", terminationReason: .exited, retryAttempt: 0))
        precondition(TransientFailureRetryPolicy.delay(retryAttempt: 0) == 2)
        precondition(TransientFailureRetryPolicy.delay(retryAttempt: 1) == 5)
    }
}
