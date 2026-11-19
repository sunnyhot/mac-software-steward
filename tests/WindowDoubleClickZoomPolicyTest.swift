import Foundation

@main
struct WindowDoubleClickZoomPolicyTest {
    static func main() throws {
        let suiteName = "WindowDoubleClickZoomPolicyTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create test defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        WindowDoubleClickZoomPolicy.enable(defaults: defaults)
        precondition(defaults.string(forKey: WindowDoubleClickZoomPolicy.actionKey) == "Maximize")

        let appSource = try String(
            contentsOfFile: "native/MacSoftwareSteward/App.swift",
            encoding: .utf8
        )
        precondition(appSource.contains("applicationWillFinishLaunching"))
        precondition(appSource.contains("WindowDoubleClickZoomPolicy.enable()"))
        precondition(!appSource.contains("onTapGesture(count: 2)"))
    }
}
