import Foundation

@main
struct BrewCaskCleanupDetectorTest {
    static func main() {
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
    }
}
