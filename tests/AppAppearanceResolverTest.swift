import SwiftUI

@main
struct AppAppearanceResolverTest {
    static func main() {
        precondition(AppAppearanceResolver.colorScheme(for: .system) == nil)
        precondition(AppAppearanceResolver.colorScheme(for: .light) == .light)
        precondition(AppAppearanceResolver.colorScheme(for: .dark) == .dark)
    }
}
