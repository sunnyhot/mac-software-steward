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

        let outlookFile = directory.appendingPathComponent("def--Microsoft_Outlook_16.109_Installer.pkg.incomplete")
        try Data(repeating: 2, count: 80).write(to: outlookFile)
        let outlook = try HomebrewDownloadMonitor.snapshot(packageName: "microsoft-outlook", in: directory, previous: nil, now: Date(timeIntervalSince1970: 30))
        precondition(outlook?.fileURL.lastPathComponent == outlookFile.lastPathComponent, "Expected underscore file name to match microsoft-outlook token")

        let unrelated = try HomebrewDownloadMonitor.snapshot(packageName: "warp", in: directory, previous: nil, now: Date(timeIntervalSince1970: 40))
        precondition(unrelated == nil, "Unrelated incomplete files must not be matched")

        precondition(HomebrewDownloadMonitor.canApplySnapshot(toPhase: "安装中"), "Active incomplete downloads must be allowed to correct premature installing phase")
        precondition(!HomebrewDownloadMonitor.canApplySnapshot(toPhase: "替换应用"), "Cache download snapshots must not override real app replacement phase")
        precondition(!HomebrewDownloadMonitor.canApplySnapshot(toPhase: "清理中"), "Cache download snapshots must not override cleanup phase")
    }
}
