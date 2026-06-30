import Foundation

@main
struct HomebrewDownloadMonitorTest {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomebrewDownloadMonitorTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let androidFile = directory.appendingPathComponent("abc--android-studio-quail1-mac_arm.dmg.incomplete")
        try Data(repeating: 1, count: 50).write(to: androidFile)
        let first = try HomebrewDownloadMonitor.snapshot(packageName: "android-studio", in: directory, previous: nil, now: Date(timeIntervalSince1970: 10))
        precondition(first?.byteCount == 50, "Expected android-studio incomplete size")

        try Data(repeating: 1, count: 150).write(to: androidFile)
        let second = try HomebrewDownloadMonitor.snapshot(packageName: "android-studio", in: directory, previous: first, now: Date(timeIntervalSince1970: 20))
        precondition(second?.byteCount == 150, "Expected android-studio size to grow")
        precondition(abs((second?.speedBytesPerSecond ?? 0) - 10) < 0.001, "Expected inferred speed from file growth")

        let hinted = try HomebrewDownloadMonitor.snapshot(
            packageName: "android-studio",
            in: directory,
            previous: first,
            now: Date(timeIntervalSince1970: 20),
            expectedByteCountHint: 200
        )
        precondition(abs((hinted?.downloadFraction ?? 0) - 0.75) < 0.001, "Expected hint-based fraction")
        precondition(hinted?.downloadSizeText.contains("/") == true, "Expected downloaded / total size")
        precondition(hinted?.downloadTimeRemainingText == "剩余 5 秒", "Expected ETA from hinted total and speed")

        let outlookFile = directory.appendingPathComponent("def--Microsoft_Outlook_16.109_Installer.pkg.incomplete")
        try Data(repeating: 2, count: 80).write(to: outlookFile)
        let outlook = try HomebrewDownloadMonitor.snapshot(packageName: "microsoft-outlook", in: directory, previous: nil, now: Date(timeIntervalSince1970: 30))
        precondition(outlook?.fileURL.lastPathComponent == outlookFile.lastPathComponent, "Expected underscore file name to match microsoft-outlook token")

        let unrelated = try HomebrewDownloadMonitor.snapshot(packageName: "warp", in: directory, previous: nil, now: Date(timeIntervalSince1970: 40))
        precondition(unrelated == nil, "Unrelated incomplete files must not be matched")

        let warpFile = directory.appendingPathComponent("ghi--warp.dmg.incomplete")
        try Data(repeating: 3, count: 90).write(to: warpFile)
        let otherFile = directory.appendingPathComponent("jkl--visual-studio-code.zip.incomplete")
        try Data(repeating: 4, count: 120).write(to: otherFile)

        let matchedWarp = try HomebrewDownloadMonitor.matchingIncompleteFile(packageName: "warp", in: directory)
        precondition(matchedWarp?.lastPathComponent == warpFile.lastPathComponent)

        let removedWarp = try HomebrewDownloadMonitor.removeIncompleteDownload(packageName: "warp", in: directory)
        precondition(removedWarp?.lastPathComponent == warpFile.lastPathComponent)
        precondition(!FileManager.default.fileExists(atPath: warpFile.path), "Expected only warp incomplete file to be removed")
        precondition(FileManager.default.fileExists(atPath: otherFile.path), "Unrelated incomplete file must remain")

        precondition(HomebrewDownloadMonitor.canApplySnapshot(toPhase: "安装中"), "Active incomplete downloads must be allowed to correct premature installing phase")
        precondition(!HomebrewDownloadMonitor.canApplySnapshot(toPhase: "替换应用"), "Cache download snapshots must not override real app replacement phase")
        precondition(!HomebrewDownloadMonitor.canApplySnapshot(toPhase: "清理中"), "Cache download snapshots must not override cleanup phase")
    }
}
