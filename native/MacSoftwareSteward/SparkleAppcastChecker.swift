import Foundation

struct SparkleAppcastCheckResult: Hashable {
    var availableVersion: String
    var diagnostic: String
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
            guard let version = parseLatestVersion(from: data), !version.isEmpty else {
                return SparkleAppcastCheckResult(availableVersion: "", diagnostic: "Sparkle feed 未找到可用版本。")
            }
            if isNewerVersion(version, than: installedVersion) {
                return SparkleAppcastCheckResult(availableVersion: version, diagnostic: "Sparkle feed 发现版本 \(version)。")
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
        let parser = SparkleAppcastVersionParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { return nil }
        return parser.version
    }

    static func isNewerVersion(_ candidate: String, than installed: String) -> Bool {
        candidate.compare(installed, options: [.numeric, .caseInsensitive]) == .orderedDescending
    }
}

private final class SparkleAppcastVersionParser: NSObject, XMLParserDelegate {
    var version: String?
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
        if name == "enclosure" {
            version = attributeDict["sparkle:shortVersionString"]
                ?? attributeDict["sparkle:version"]
                ?? attributeDict["shortVersionString"]
                ?? attributeDict["version"]
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
            if version == nil, !trimmed.isEmpty {
                version = trimmed
            }
            captureVersionText = false
        }
    }
}
