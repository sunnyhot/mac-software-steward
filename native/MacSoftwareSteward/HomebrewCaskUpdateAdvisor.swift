import Foundation

struct HomebrewCaskMetadata: Hashable {
    var token: String
    var version: String
    var autoUpdates: Bool
    var releaseFeedURLString: String
    var releasePageURLString: String
}

struct HomebrewCaskUpdateAdvisory: Hashable {
    var token: String
    var currentVersion: String
    var sourceURLString: String
    var diagnostic: String
}

enum HomebrewCaskUpdateAdvisor {
    static func parseMetadata(from stdout: String) -> [String: HomebrewCaskMetadata] {
        guard
            let data = stdout.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let casks = object["casks"] as? [[String: Any]]
        else {
            return [:]
        }

        let pairs = casks.compactMap { item -> (String, HomebrewCaskMetadata)? in
            guard let metadata = metadata(from: item) else { return nil }
            return (metadata.token, metadata)
        }
        return Dictionary(pairs, uniquingKeysWith: { _, last in last })
    }

    static func check(
        metadata: HomebrewCaskMetadata,
        installedVersion: String,
        timeout: TimeInterval = 8
    ) async -> HomebrewCaskUpdateAdvisory? {
        guard metadata.autoUpdates,
              !metadata.releaseFeedURLString.isEmpty,
              let url = URL(string: metadata.releaseFeedURLString) else {
            return nil
        }

        do {
            let request = URLRequest(url: url, timeoutInterval: timeout)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            guard let version = parseLatestVersion(from: data), !version.isEmpty else {
                return nil
            }
            let baseline = installedVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? metadata.version
                : installedVersion
            guard SparkleAppcastChecker.isNewerVersion(version, than: baseline) else {
                return nil
            }
            return HomebrewCaskUpdateAdvisory(
                token: metadata.token,
                currentVersion: version,
                sourceURLString: metadata.releasePageURLString,
                diagnostic: "GitHub Releases 发现版本 \(version)。"
            )
        } catch {
            return nil
        }
    }

    static func parseLatestVersion(from data: Data) -> String? {
        let parser = GitHubReleaseAtomParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { return nil }
        return parser.latestVersion
    }

    private static func metadata(from item: [String: Any]) -> HomebrewCaskMetadata? {
        let token = string(item["token"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }

        let version = string(item["version"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let autoUpdates = item["auto_updates"] as? Bool ?? false
        let url = string(item["url"])
        let homepage = string(item["homepage"])
        let verified = (item["url_specs"] as? [String: Any]).map { string($0["verified"]) } ?? ""
        let repository = githubRepository(from: [url, verified, homepage])

        return HomebrewCaskMetadata(
            token: token,
            version: version,
            autoUpdates: autoUpdates,
            releaseFeedURLString: repository.map { "https://github.com/\($0.owner)/\($0.repo)/releases.atom" } ?? "",
            releasePageURLString: repository.map { "https://github.com/\($0.owner)/\($0.repo)/releases/latest" } ?? ""
        )
    }

    private static func githubRepository(from values: [String]) -> (owner: String, repo: String)? {
        let pattern = #"github\.com[:/]+([^/\s?#]+)/([^/\s?#]+)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        for value in values {
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            guard let match = regex?.firstMatch(in: value, options: [], range: range),
                  match.numberOfRanges >= 3,
                  let ownerRange = Range(match.range(at: 1), in: value),
                  let repoRange = Range(match.range(at: 2), in: value) else {
                continue
            }
            let owner = String(value[ownerRange])
            let repo = String(value[repoRange])
                .replacingOccurrences(of: ".git", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !owner.isEmpty, !repo.isEmpty {
                return (owner, repo)
            }
        }
        return nil
    }

    private static func string(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let list as [Any]:
            return list.map { string($0) }.joined(separator: " ")
        default:
            return ""
        }
    }
}

private final class GitHubReleaseAtomParser: NSObject, XMLParserDelegate {
    var latestVersion: String?
    private var isInsideEntry = false
    private var captureTitle = false
    private var titleText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = (qName ?? elementName).lowercased()
        if name == "entry", latestVersion == nil {
            isInsideEntry = true
            return
        }
        if isInsideEntry, name == "title" {
            captureTitle = true
            titleText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if captureTitle {
            titleText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = (qName ?? elementName).lowercased()
        if name == "title", captureTitle {
            latestVersion = extractVersion(from: titleText)
            captureTitle = false
        } else if name == "entry" {
            isInsideEntry = false
        }
    }

    private func extractVersion(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let pattern = #"v?\d+(?:\.\d+)+(?:[-+][A-Za-z0-9.]+)?"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if let match = regex.firstMatch(in: trimmed, options: [], range: range),
               let matchRange = Range(match.range, in: trimmed) {
                return normalizeVersion(String(trimmed[matchRange]))
            }
        }
        return normalizeVersion(trimmed)
    }

    private func normalizeVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1,
              trimmed.first?.lowercased() == "v",
              trimmed.dropFirst().first?.isNumber == true else {
            return trimmed
        }
        return String(trimmed.dropFirst())
    }
}
