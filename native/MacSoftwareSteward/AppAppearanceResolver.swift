import SwiftUI

enum AppAppearanceResolver {
    static func colorScheme(for mode: AppearanceMode) -> ColorScheme? {
        mode.colorScheme
    }
}
