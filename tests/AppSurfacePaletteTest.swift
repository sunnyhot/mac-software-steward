import Foundation

@main
struct AppSurfacePaletteTest {
    static func main() {
        precondition(AppSurfacePalette.semanticColor(for: .canvas, appearance: .light) == .textBackground)
        precondition(AppSurfacePalette.semanticColor(for: .surface, appearance: .light) == .textBackground)
        precondition(AppSurfacePalette.semanticColor(for: .sidebar, appearance: .light) == .windowBackground)
        precondition(AppSurfacePalette.opacity(for: .canvas, appearance: .light) == 1.0)
        precondition(AppSurfacePalette.opacity(for: .surface, appearance: .light) == 1.0)
        precondition(AppSurfacePalette.tintOpacity(isActive: false, appearance: .light) <= 0.02)

        precondition(AppSurfacePalette.semanticColor(for: .canvas, appearance: .dark) == .windowBackground)
        precondition(AppSurfacePalette.semanticColor(for: .surface, appearance: .dark) == .controlBackground)
        precondition(AppSurfacePalette.tintOpacity(isActive: false, appearance: .dark) > AppSurfacePalette.tintOpacity(isActive: false, appearance: .light))
    }
}
