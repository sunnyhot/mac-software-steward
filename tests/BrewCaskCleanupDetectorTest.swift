import Foundation

@main
struct BrewCaskCleanupDetectorTest {
    static func main() {
        precondition(!BrewCaskCleanupDetector.hasStaleInstallRecord(expectedAppPaths: []))
        precondition(BrewCaskCleanupDetector.hasStaleInstallRecord(
            expectedAppPaths: ["/Applications/Missing.app"],
            fileExists: { _ in false }
        ))
        precondition(!BrewCaskCleanupDetector.hasStaleInstallRecord(
            expectedAppPaths: ["/Applications/Present.app", "/Applications/Missing.app"],
            fileExists: { $0.hasSuffix("Present.app") }
        ))

        let command = UpgradeCommand(
            executable: "/opt/homebrew/bin/brew",
            arguments: ["upgrade", "--cask", "--greedy", "microsoft-excel"],
            display: "brew upgrade --cask --greedy microsoft-excel"
        )
        let output = """
        [stdout] ==> Fetching downloads for: microsoft-excel
        [stderr] Error: Download failed on Cask 'microsoft-excel' with message: Download failed: https://officecdnmac.microsoft.com/example.pkg
        [stderr] curl: (18) Transferred a partial file
        """

        let missingAppCandidate = BrewCaskCleanupDetector.cleanupCandidate(
            command: command,
            output: output,
            appPresence: BrewCaskAppPresence(scanSucceeded: true, relatedAppExists: false)
        )
        precondition(missingAppCandidate == "microsoft-excel", "Expected stale download failure to clean microsoft-excel, got \(String(describing: missingAppCandidate))")

        let existingAppCandidate = BrewCaskCleanupDetector.cleanupCandidate(
            command: command,
            output: output,
            appPresence: BrewCaskAppPresence(scanSucceeded: true, relatedAppExists: true)
        )
        precondition(existingAppCandidate == nil, "Existing related app should keep download failure as retryable")

        let unverifiedCandidate = BrewCaskCleanupDetector.cleanupCandidate(
            command: command,
            output: output,
            appPresence: BrewCaskAppPresence(scanSucceeded: false, relatedAppExists: false)
        )
        precondition(unverifiedCandidate == nil, "Failed app scan should not auto-uninstall on download failure")

        let appSourceCommand = UpgradeCommand(
            executable: "/opt/homebrew/bin/brew",
            arguments: ["upgrade", "--cask", "--greedy", "codexbar"],
            display: "brew upgrade --cask --greedy codexbar"
        )
        let appSourceOutput = "Error: codexbar: It seems the App source '/Applications/CodexBar.app' is not there."
        let appSourceCandidate = BrewCaskCleanupDetector.cleanupCandidate(
            command: appSourceCommand,
            output: appSourceOutput,
            appPresence: BrewCaskAppPresence(scanSucceeded: false, relatedAppExists: false)
        )
        precondition(appSourceCandidate == "codexbar", "App source failures should still clean without scan evidence")

        let caskroomConflictCommand = UpgradeCommand(
            executable: "/opt/homebrew/bin/brew",
            arguments: ["upgrade", "--cask", "--greedy", "iina"],
            display: "brew upgrade --cask --greedy iina"
        )
        let caskroomConflictOutput = "Error: iina: It seems there is already an App at '/opt/homebrew/Caskroom/iina/1.4.2,164/IINA.app'."
        let caskroomConflictCandidate = BrewCaskCleanupDetector.cleanupCandidate(
            command: caskroomConflictCommand,
            output: caskroomConflictOutput,
            appPresence: BrewCaskAppPresence(scanSucceeded: true, relatedAppExists: false)
        )
        precondition(caskroomConflictCandidate == "iina", "Caskroom App conflicts with a missing installed app should clean iina, got \(String(describing: caskroomConflictCandidate))")

        let applicationsConflictOutput = "Error: iina: It seems there is already an App at '/Applications/IINA.app'."
        let applicationsConflictCandidate = BrewCaskCleanupDetector.cleanupCandidate(
            command: caskroomConflictCommand,
            output: applicationsConflictOutput,
            appPresence: BrewCaskAppPresence(scanSucceeded: true, relatedAppExists: false)
        )
        precondition(applicationsConflictCandidate == nil, "Application-directory conflicts should not be treated as stale Caskroom cleanup")
    }
}
