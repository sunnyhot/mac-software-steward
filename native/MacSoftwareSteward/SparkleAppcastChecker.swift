import Foundation

struct SparkleAppcastCheckResult: Hashable {
    var availableVersion: String
    var diagnostic: String
    var downloadURLString: String? = nil
}

struct SparkleAppcastItem: Hashable {
    var version: String
    var downloadURLString: String?
}

enum SparkleAppcastChecker {
    static func check(
        feedURLString: String,
        installedVersion: String,
        timeout: TimeInterval = 8
    ) async -> SparkleAppcastCheckResult {
        guard let url = URL(string: feedURLString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return SparkleAppcastCheckResult(availableVersion: "", diagnostic: "Sparkle feed URL 无效。")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request(for: url, timeout: timeout))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return SparkleAppcastCheckResult(availableVersion: "", diagnostic: "Sparkle feed HTTP 状态码 \(http.statusCode)。")
            }
            guard let item = parseLatestItem(from: data), !item.version.isEmpty else {
                return SparkleAppcastCheckResult(availableVersion: "", diagnostic: "Sparkle feed 未找到可用版本。")
            }
            if isNewerVersion(item.version, than: installedVersion) {
                return SparkleAppcastCheckResult(
                    availableVersion: item.version,
                    diagnostic: "Sparkle feed 发现版本 \(item.version)。",
                    downloadURLString: item.downloadURLString
                )
            }
            return SparkleAppcastCheckResult(availableVersion: "", diagnostic: "Sparkle feed 未发现更新。")
        } catch {
            return SparkleAppcastCheckResult(availableVersion: "", diagnostic: diagnostic(for: error))
        }
    }

    static func request(for url: URL, timeout: TimeInterval = 8) -> URLRequest {
        URLRequest(url: url, timeoutInterval: timeout)
    }

    static func diagnostic(for error: Error) -> String {
        if (error as? URLError)?.code == .timedOut {
            return "Sparkle feed 检查超时。"
        }
        return "Sparkle feed 检查失败：\(error.localizedDescription)"
    }

    static func parseLatestVersion(from data: Data) -> String? {
        parseLatestItem(from: data)?.version
    }

    static func parseLatestItem(from data: Data) -> SparkleAppcastItem? {
        let parser = SparkleAppcastItemParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { return nil }
        return parser.item
    }

    static func isNewerVersion(_ candidate: String, than installed: String) -> Bool {
        candidate.compare(installed, options: [.numeric, .caseInsensitive]) == .orderedDescending
    }
}

private final class SparkleAppcastItemParser: NSObject, XMLParserDelegate {
    var item: SparkleAppcastItem?
    private var currentVersion: String?
    private var currentDownloadURLString: String?
    private var isInsideItem = false
    private var captureVersionText = false
    private var versionText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = (qName ?? elementName).lowercased()
        if name == "item" {
            isInsideItem = true
            currentVersion = nil
            currentDownloadURLString = nil
            return
        }
        if name == "enclosure" {
            let version = attributeDict["sparkle:shortVersionString"]
                ?? attributeDict["sparkle:version"]
                ?? attributeDict["shortVersionString"]
                ?? attributeDict["version"]
            let downloadURLString = attributeDict["url"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            capture(version: version, downloadURLString: downloadURLString)
        } else if name == "sparkle:version" || name == "version" {
            captureVersionText = true
            versionText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if captureVersionText {
            versionText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = (qName ?? elementName).lowercased()
        if name == "sparkle:version" || name == "version" {
            let trimmed = versionText.trimmingCharacters(in: .whitespacesAndNewlines)
            capture(version: trimmed, downloadURLString: nil)
            captureVersionText = false
        } else if name == "item" {
            publishCurrentItemIfNeeded()
            isInsideItem = false
        }
    }

    private func capture(version: String?, downloadURLString: String?) {
        if let version = version?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty {
            currentVersion = currentVersion ?? version
        }
        if let downloadURLString, !downloadURLString.isEmpty {
            currentDownloadURLString = currentDownloadURLString ?? downloadURLString
        }
        if !isInsideItem {
            publishCurrentItemIfNeeded()
        }
    }

    private func publishCurrentItemIfNeeded() {
        guard item == nil,
              let version = currentVersion,
              !version.isEmpty else { return }
        item = SparkleAppcastItem(
            version: version,
            downloadURLString: currentDownloadURLString
        )
    }
}
