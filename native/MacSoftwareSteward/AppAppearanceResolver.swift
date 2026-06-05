import AppKit
import SwiftUI

enum AppAppearanceResolver {
    static func colorScheme(for mode: AppearanceMode) -> ColorScheme? {
        mode.colorScheme
    }

    static func nsAppearanceName(for mode: AppearanceMode) -> NSAppearance.Name? {
        switch mode {
        case .system:
            return nil
        case .light:
            return .aqua
        case .dark:
            return .darkAqua
        }
    }

    @MainActor
    static func apply(_ mode: AppearanceMode) {
        let appearance = nsAppearanceName(for: mode).flatMap(NSAppearance.init(named:))
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }
}
