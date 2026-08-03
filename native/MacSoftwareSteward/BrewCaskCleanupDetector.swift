import Foundation

struct BrewCaskAppPresence {
    var scanSucceeded: Bool
    var relatedAppExists: Bool
}

enum BrewCaskCleanupDetector {
    static func hasStaleInstallRecord(
        expectedAppPaths: [String],
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> Bool {
        !expectedAppPaths.isEmpty && expectedAppPaths.allSatisfy { !fileExists($0) }
    }

    static func cleanupCandidate(
        command: UpgradeCommand,
        output: String,
        appPresence: BrewCaskAppPresence
    ) -> String? {
        guard isBrewCaskUpgrade(command) else { return nil }
        guard let caskName = caskName(from: command) else { return nil }

        let lowercased = output.lowercased()
        if lowercased.contains("app source"), lowercased.contains("is not there") {
            return caskName
        }

        if isDownloadFailure(lowercased), appPresence.scanSucceeded, !appPresence.relatedAppExists {
            return caskName
        }

        if isCaskroomAppConflict(lowercased), appPresence.scanSucceeded, !appPresence.relatedAppExists {
            return caskName
        }

        return nil
    }

    private static func isBrewCaskUpgrade(_ command: UpgradeCommand) -> Bool {
        command.arguments.contains("upgrade") && command.arguments.contains("--cask")
    }

    private static func caskName(from command: UpgradeCommand) -> String? {
        command.arguments.reversed().first { argument in
            !argument.hasPrefix("-") && argument != "upgrade"
        }
    }

    private static func isDownloadFailure(_ lowercasedOutput: String) -> Bool {
        lowercasedOutput.contains("download failed on cask")
            || lowercasedOutput.contains("download failed:")
            || lowercasedOutput.contains("curl: (18)")
    }

    static func isCaskroomAppConflict(_ lowercasedOutput: String) -> Bool {
        lowercasedOutput.contains("already an app at")
            && lowercasedOutput.contains("/caskroom/")
    }
}
