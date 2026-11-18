import Foundation

/// 只对可能自行恢复的错误做有限重试；权限、配置、校验等问题不盲目重复。
enum TransientFailureRetryPolicy {
    static let maxRetries = 2

    static func shouldRetry(
        code: Int32,
        output: String,
        terminationReason: CommandTerminationReason,
        retryAttempt: Int
    ) -> Bool {
        guard code != 0,
              terminationReason == .exited,
              retryAttempt >= 0,
              retryAttempt < maxRetries else { return false }
        let text = output.lowercased()
        guard !text.isEmpty else { return false }

        let permanentMarkers = [
            "permission denied", "operation not permitted", "sudo", "password",
            "user canceled", "user cancelled", "syntax error", "checksum", "sha256",
            "already exists", "not found", "no space left", "invalid", "caskroom",
            "unknown command", "app is damaged", "requires administrator"
        ]
        guard !permanentMarkers.contains(where: { text.contains($0) }) else { return false }

        let transientMarkers = [
            "download failed", "failed to download", "failed to fetch", "couldn't resolve host",
            "could not resolve host", "connection timed out", "connection reset", "connection refused",
            "network is unreachable", "network error", "temporary failure", "timed out", "timeout",
            "http error 502", "http error 503", "http error 504", "bad gateway",
            "service unavailable", "curl error", "socket error", "ssl error", "tls error"
        ]
        return transientMarkers.contains { text.contains($0) }
    }

    static func delay(retryAttempt: Int) -> TimeInterval {
        retryAttempt == 0 ? 2 : 5
    }
}
