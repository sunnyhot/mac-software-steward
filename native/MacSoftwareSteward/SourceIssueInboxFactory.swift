import Foundation

enum SourceIssueInboxFactory {
    static func items(from scan: ScanResult) -> [InboxItem] {
        [brewItem(from: scan.brew), masItem(from: scan.mas)]
            .compactMap { $0 }
    }

    private static func brewItem(from brew: BrewScan) -> InboxItem? {
        if !brew.available {
            return item(
                severity: .warning,
                title: "Homebrew 来源需要处理",
                summary: "未检测到 Homebrew，Homebrew 软件扫描和升级不可用。",
                sourceID: "source:homebrew"
            )
        }
        guard !brew.error.isEmpty else { return nil }
        return item(
            severity: .warning,
            title: "Homebrew 来源需要处理",
            summary: "Homebrew 扫描遇到错误：\(trimmed(brew.error))",
            sourceID: "source:homebrew"
        )
    }

    private static func masItem(from mas: MasScan) -> InboxItem? {
        if !mas.available {
            return item(
                severity: .info,
                title: "App Store 来源需要处理",
                summary: "未检测到 mas CLI，App Store 应用扫描和升级不可用。",
                sourceID: "source:mas"
            )
        }
        guard !mas.error.isEmpty else { return nil }
        return item(
            severity: .warning,
            title: "App Store 来源需要处理",
            summary: "App Store 扫描遇到错误：\(trimmed(mas.error))",
            sourceID: "source:mas"
        )
    }

    private static func item(
        severity: InboxSeverity,
        title: String,
        summary: String,
        sourceID: String
    ) -> InboxItem {
        InboxItem(
            kind: .sourceIssue,
            severity: severity,
            title: title,
            summary: summary,
            sourceID: sourceID,
            actions: [
                InboxAction(title: "查看来源诊断", systemImage: "stethoscope", kind: .openSources),
                InboxAction(title: "重新扫描", systemImage: "arrow.clockwise", kind: .rescan)
            ]
        )
    }

    private static func trimmed(_ text: String) -> String {
        let singleLine = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first ?? text
        let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未知错误" : trimmed
    }
}
