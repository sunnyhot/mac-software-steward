import Foundation

// MARK: - Residual File Scanner
actor ResidualScanner {

    // MARK: - Dependencies
    private let safeRemover = SafeRemover()

    // MARK: - Scan Patterns
    private let scanPatterns: [ResidualPattern] = [
        // Application Support
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Application Support",
            pattern: "{bundleId}*",
            category: .support,
            riskLevel: .moderate,
            description: "Application Support files"
        ),

        // Preferences
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Preferences",
            pattern: "com.{vendor}.*",
            category: .preference,
            riskLevel: .moderate,
            description: "Application preferences"
        ),

        // Caches
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Caches",
            pattern: "{bundleId}*",
            category: .cache,
            riskLevel: .safe,
            description: "Cache files"
        ),

        // Logs
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Logs",
            pattern: "{bundleId}*",
            category: .log,
            riskLevel: .safe,
            description: "Log files"
        ),

        // Launch Agents
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/LaunchAgents",
            pattern: "com.{vendor}.*",
            category: .launchAgent,
            riskLevel: .caution,
            description: "Launch agents"
        ),

        // Launch Daemons (system level)
        ResidualPattern(
            basePath: "/Library/LaunchAgents",
            pattern: "com.{vendor}.*",
            category: .launchAgent,
            riskLevel: .caution,
            description: "Launch agents (system)"
        ),

        // WebKit Data
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/WebKit",
            pattern: "{bundleId}",
            category: .webkit,
            riskLevel: .moderate,
            description: "WebKit data"
        ),

        // Containers
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Containers",
            pattern: "{bundleId}",
            category: .container,
            riskLevel: .moderate,
            description: "App containers"
        ),

        // Group Containers
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Group Containers",
            pattern: "{group}",
            category: .container,
            riskLevel: .moderate,
            description: "Group containers"
        ),

        // Saved Application State
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Saved Application State",
            pattern: "{bundleId}.*",
            category: .savedAppState,
            riskLevel: .safe,
            description: "Saved application state"
        ),

        // HTTP Storage
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/HTTPStorages",
            pattern: "{bundleId}",
            category: .httpStorage,
            riskLevel: .safe,
            description: "HTTP storage"
        ),

        // HTTP Cookies
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/HTTPCookies",
            pattern: "{bundleId}",
            category: .cookies,
            riskLevel: .caution,
            description: "HTTP cookies"
        ),

        // ByHost Preferences
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Preferences/ByHost",
            pattern: "{bundleId}.*",
            category: .preference,
            riskLevel: .moderate,
            description: "ByHost preferences"
        ),

        // Cookies
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Cookies",
            pattern: "{bundleId}*",
            category: .cookies,
            riskLevel: .caution,
            description: "Cookie files"
        ),

        // Trash
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/.Trash",
            pattern: "{appname}*",
            category: .trash,
            riskLevel: .safe,
            description: "Trash files"
        )
    ]

    // MARK: - Public Methods

    /// Find residual files for a given bundle ID
    func findResidualFiles(bundleId: String, appName: String) async throws -> [ResidualFile] {
        var residuals: [ResidualFile] = []
        let vendor = extractVendor(from: bundleId)

        // Extract group identifier from bundle ID if available
        let groupIdentifier = extractGroupIdentifier(from: bundleId)

        for pattern in scanPatterns {
            let searchPattern = pattern.pattern
                .replacingOccurrences(of: "{bundleId}", with: bundleId)
                .replacingOccurrences(of: "{vendor}", with: vendor)
                .replacingOccurrences(of: "{group}", with: groupIdentifier)
                .replacingOccurrences(of: "{appname}", with: appName)

            if let found = await searchForPattern(
                basePath: pattern.basePath,
                pattern: searchPattern,
                category: pattern.category,
                riskLevel: pattern.riskLevel,
                description: pattern.description
            ) {
                residuals.append(contentsOf: found)
            }
        }

        return residuals
    }

    // MARK: - Private Methods

    private func searchForPattern(
        basePath: String,
        pattern: String,
        category: ResidualFile.ResidualCategory,
        riskLevel: ResidualFile.RiskLevel,
        description: String
    ) async -> [ResidualFile]? {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: basePath) else {
            return nil
        }

        var results: [ResidualFile] = []

        do {
            let baseURL = URL(fileURLWithPath: basePath)

            // Convert shell pattern to regex
            let regexPattern = convertShellPatternToRegex(pattern)

            if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let url as URL in enumerator {
                    let fileName = url.lastPathComponent

                    if matchesPattern(fileName, pattern: regexPattern) {
                        // Skip protected paths
                        if await safeRemover.isProtectedPath(url) {
                            continue
                        }

                        let size = await getFileSize(at: url)

                        let residual = ResidualFile(
                            path: url,
                            size: size,
                            category: category,
                            riskLevel: riskLevel,
                            description: description
                        )

                        results.append(residual)
                    }
                }
            }
        } catch {
            return nil
        }

        return results.isEmpty ? nil : results
    }

    private func extractVendor(from bundleId: String) -> String {
        let components = bundleId.split(separator: ".")
        if components.count >= 2 {
            return String(components[1])
        }
        return bundleId
    }

    private func extractGroupIdentifier(from bundleId: String) -> String {
        // Try to extract group identifier from bundle ID
        // Usually something like "group.com.example.app"
        return "group.\(bundleId)"
    }

    private func convertShellPatternToRegex(_ pattern: String) -> String {
        // First escape special regex characters (except *)
        let escapedPattern = NSRegularExpression.escapedPattern(for: pattern)

        // Now convert shell wildcards to regex
        var regex = escapedPattern.replacingOccurrences(of: "\\*", with: ".*")

        // Add anchors
        regex = "^\(regex)$"

        return regex
    }

    private func matchesPattern(_ fileName: String, pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(fileName.startIndex..., in: fileName)
            return regex.firstMatch(in: fileName, range: range) != nil
        } catch {
            return false
        }
    }

    private func getFileSize(at url: URL) async -> Int64 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default

                do {
                    let attributes = try fileManager.attributesOfItem(atPath: url.path)
                    if let fileSize = attributes[.size] as? Int64 {
                        continuation.resume(returning: fileSize)
                    } else {
                        continuation.resume(returning: 0)
                    }
                } catch {
                    continuation.resume(returning: 0)
                }
            }
        }
    }

    // MARK: - Supporting Types

    private struct ResidualPattern {
        let basePath: String
        let pattern: String
        let category: ResidualFile.ResidualCategory
        let riskLevel: ResidualFile.RiskLevel
        let description: String
    }
}