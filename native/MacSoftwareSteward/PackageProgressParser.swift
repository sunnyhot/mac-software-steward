import Foundation

struct ParsedPackageProgress: Hashable {
    var phaseText: String?
    var detail: String
    var downloadFraction: Double?
    var downloadSizeText: String?
    var downloadSpeedText: String?
    var clearsDownloadProgress = false
}

enum PackageProgressParser {
    static func parse(stream: String, text: String) -> ParsedPackageProgress {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if stream == "command" {
            return ParsedPackageProgress(
                phaseText: "执行命令",
                detail: trimmed.replacingOccurrences(of: "$ ", with: "")
            )
        }

        if lowercased.contains("fetching downloads for:") {
            return ParsedPackageProgress(
                phaseText: "准备下载",
                detail: "准备下载 \(suffix(after: "for:", in: trimmed))",
                downloadFraction: 0
            )
        }

        if lowercased.contains("already downloaded") {
            return ParsedPackageProgress(
                phaseText: "下载完成",
                detail: "下载完成",
                downloadFraction: 1
            )
        }

        if lowercased.contains("downloaded to:") {
            return ParsedPackageProgress(
                phaseText: "下载完成",
                detail: "下载完成",
                downloadFraction: 1
            )
        }

        if lowercased.contains("downloading") {
            let fraction = percentFraction(in: trimmed) ?? 0
            return ParsedPackageProgress(
                phaseText: "下载中",
                detail: "正在下载",
                downloadFraction: fraction
            )
        }

        if let curl = curlProgress(from: trimmed) {
            return curl
        }

        if lowercased.contains("verifying") && (lowercased.contains("checksum") || lowercased.contains("sha")) {
            return phase("校验下载", "校验下载文件")
        }

        if lowercased.contains("installing app") {
            return phase("安装中", "安装中 \(quotedAppName(in: trimmed) ?? "应用")")
        }

        if lowercased.contains("moving app") || lowercased.contains("backing app") {
            return phase("替换应用", "替换旧版本应用")
        }

        if lowercased.contains("installing") || lowercased.contains("upgrading") || lowercased.contains("reinstalling") || lowercased.contains("pouring") {
            return phase("安装中", trimmed.withoutBrewPrefix)
        }

        if lowercased.contains("linking binary") {
            return phase("链接命令", trimmed.withoutBrewPrefix)
        }

        if lowercased.contains("unlinking binary") {
            return phase("移除旧链接", trimmed.withoutBrewPrefix)
        }

        if lowercased.contains("purging files") || lowercased.contains("cleanup") || lowercased.contains("cleaning") {
            return phase("清理中", trimmed.withoutBrewPrefix)
        }

        return ParsedPackageProgress(
            phaseText: nil,
            detail: "[\(stream)] \(trimmed)"
        )
    }

    private static func phase(_ phaseText: String, _ detail: String) -> ParsedPackageProgress {
        ParsedPackageProgress(
            phaseText: phaseText,
            detail: detail,
            clearsDownloadProgress: true
        )
    }

    private static func suffix(after marker: String, in text: String) -> String {
        guard let range = text.range(of: marker, options: [.caseInsensitive, .backwards]) else {
            return text.withoutBrewPrefix
        }
        return text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func quotedAppName(in text: String) -> String? {
        guard let first = text.firstIndex(of: "'"),
              let second = text[text.index(after: first)...].firstIndex(of: "'") else {
            return nil
        }
        return String(text[text.index(after: first)..<second])
    }

    private static func percentFraction(in text: String) -> Double? {
        guard let pctRange = text.range(of: #"(\d+\.?\d*)\s*%"#, options: .regularExpression) else {
            return nil
        }
        let pctString = text[pctRange]
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let pct = Double(pctString) else { return nil }
        return min(max(pct / 100.0, 0), 1)
    }

    private static func curlProgress(from text: String) -> ParsedPackageProgress? {
        let parts = text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard parts.count >= 12,
              let pct = Double(parts[0]),
              pct >= 0,
              pct <= 100,
              looksLikeCurlTime(parts[9]),
              looksLikeCurlTime(parts[10]) else {
            return nil
        }

        let total = parts[1]
        let received = parts[3]
        let currentSpeed = normalizedSpeed(parts[11])
        return ParsedPackageProgress(
            phaseText: "下载中",
            detail: "正在下载",
            downloadFraction: pct / 100.0,
            downloadSizeText: "\(received) / \(total)",
            downloadSpeedText: currentSpeed
        )
    }

    private static func looksLikeCurlTime(_ text: String) -> Bool {
        text.contains(":") || text == "--:--:--"
    }

    private static func normalizedSpeed(_ text: String) -> String {
        if text.contains("/s") { return text }
        return "\(text)/s"
    }
}

private extension String {
    var withoutBrewPrefix: String {
        if hasPrefix("==>") {
            return dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return self
    }
}
