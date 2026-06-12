import CryptoKit
import Foundation

enum AppUpdateSecurityError: LocalizedError, Equatable {
    case missingExpectedSHA256
    case sha256Mismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .missingExpectedSHA256:
            return "更新清单缺少安装包校验值。"
        case .sha256Mismatch:
            return "下载文件校验失败，请稍后重试。"
        }
    }
}

enum AppUpdateSecurity {
    static func sha256Hex(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func verifySHA256(fileURL: URL, expectedSHA256: String) throws {
        let expected = expectedSHA256
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !expected.isEmpty else {
            throw AppUpdateSecurityError.missingExpectedSHA256
        }

        let actual = try sha256Hex(of: fileURL)
        guard actual == expected else {
            throw AppUpdateSecurityError.sha256Mismatch(expected: expected, actual: actual)
        }
    }
}
