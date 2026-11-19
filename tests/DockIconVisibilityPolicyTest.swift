import Foundation

@main
struct DockIconVisibilityPolicyTest {
    static func main() throws {
        let suiteName = "DockIconVisibilityPolicyTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create test defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        precondition(DockIconVisibilityPolicy.showsDock(defaults: defaults), "Dock should default to visible")
        defaults.set(false, forKey: DockIconVisibilityPolicy.defaultsKey)
        precondition(!DockIconVisibilityPolicy.showsDock(defaults: defaults))

        let appSource = try String(contentsOfFile: "native/MacSoftwareSteward/App.swift", encoding: .utf8)
        precondition(appSource.contains("onChange(of: dockIconVisible)"))
        precondition(appSource.contains("DockIconVisibilityPolicy.apply()"))
    }
}
