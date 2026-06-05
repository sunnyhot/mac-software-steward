import AppKit
import Foundation

@main
struct AppAppearanceResolverTest {
    static func main() {
        precondition(AppAppearanceResolver.nsAppearanceName(for: .system) == nil)
        precondition(AppAppearanceResolver.nsAppearanceName(for: .light) == .aqua)
        precondition(AppAppearanceResolver.nsAppearanceName(for: .dark) == .darkAqua)
        precondition(AppAppearanceResolver.colorScheme(for: .system) == nil)
        precondition(AppAppearanceResolver.colorScheme(for: .light) == .light)
        precondition(AppAppearanceResolver.colorScheme(for: .dark) == .dark)
    }
}
