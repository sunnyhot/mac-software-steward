import Foundation

enum HomebrewCaskDownloadSizeResolver {
    static func resolve(caskName: String, brewExecutable: String) async -> Int64? {
        let info = await CommandRunner.run(
            brewExecutable,
            arguments: ["info", "--cask", "--json=v2", caskName],
            timeout: 30
        )
        guard info.ok, let url = caskURL(from: info.stdout, caskName: caskName) else { return nil }

        let headers = await CommandRunner.run(
            "/usr/bin/curl",
            arguments: ["-I", "-L", "--connect-timeout", "10", "--max-time", "20", url],
            timeout: 25
        )
        guard headers.ok else { return nil }
        return expectedByteCount(fromHeaders: headers.stdout)
    }

    static func caskURL(from json: String, caskName: String) -> String? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]] else { return nil }

        let selected = casks.first { ($0["token"] as? String) == caskName } ?? casks.first
        return selected?["url"] as? String
    }

    static func expectedByteCount(fromHeaders headers: String) -> Int64? {
        for line in headers.components(separatedBy: .newlines).reversed() {
            guard let range = line.range(of: #"content-range:\s*bytes\s+\d+-\d+/(\d+)"#, options: [.regularExpression, .caseInsensitive]) else { continue }
            let match = String(line[range])
            if let total = match.split(separator: "/").last.flatMap({ Int64($0.trimmingCharacters(in: .whitespaces)) }) {
                return total
            }
        }

        for line in headers.components(separatedBy: .newlines).reversed() {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let name = parts[0].lowercased()
            if name == "x-identity-content-length" || name == "content-length" {
                return Int64(parts[1])
            }
        }
        return nil
    }
}
