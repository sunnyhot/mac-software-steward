import AppKit
import Foundation

enum DockIconVisibilityPolicy {
    static let defaultsKey = "dockIconVisible"

    static func showsDock(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }

    static func apply(defaults: UserDefaults = .standard) {
        NSApp.setActivationPolicy(showsDock(defaults: defaults) ? .regular : .accessory)
    }
}
