import Foundation

@main
struct ManualAppReplacementInstallerTest {
    static func main() throws {
        precondition(ManualAppReplacementInstaller.archiveKind(for: URL(fileURLWithPath: "/tmp/App.zip")) == .zip)
        precondition(ManualAppReplacementInstaller.archiveKind(for: URL(fileURLWithPath: "/tmp/App.dmg")) == .dmg)
        precondition(ManualAppReplacementInstaller.archiveKind(for: URL(fileURLWithPath: "/tmp/App.pkg")) == nil)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("manual-app-replacement-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("Payload", isDirectory: true)
        let existingApp = try makeApp(root: root, name: "Existing", bundleID: "com.example.app")
        let replacementApp = try makeApp(root: nested, name: "Replacement", bundleID: "com.example.app")
        let wrongApp = try makeApp(root: nested, name: "Wrong", bundleID: "com.example.other")

        precondition(ManualAppReplacementInstaller.findApp(in: root)?.pathExtension == "app")
        try ManualAppReplacementInstaller.validateReplacement(existingAppURL: existingApp, newAppURL: replacementApp)

        do {
            try ManualAppReplacementInstaller.validateReplacement(existingAppURL: existingApp, newAppURL: wrongApp)
            preconditionFailure("Mismatched bundle ids must be rejected")
        } catch let error as ManualAppReplacementError {
            precondition(error.localizedDescription.contains("应用标识不一致"))
        }

        let hdiutilOutput = "/dev/disk4s1\tApple_HFS\t/Volumes/Test App\n"
        precondition(ManualAppReplacementInstaller.mountPoint(fromHdiutilOutput: hdiutilOutput)?.path == "/Volumes/Test App")
    }

    private static func makeApp(root: URL, name: String, bundleID: String) throws -> URL {
        let appURL = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let plist = [
            "CFBundleIdentifier": bundleID,
            "CFBundleShortVersionString": "1.0"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        return appURL
    }
}
