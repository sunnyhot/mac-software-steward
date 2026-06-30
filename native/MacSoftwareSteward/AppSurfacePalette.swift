import AppKit

enum AppSurfaceAppearance {
    case light
    case dark
}

enum AppSurfaceRole {
    case canvas
    case sidebar
    case surface
}

enum AppSurfaceSemanticColor {
    case textBackground
    case windowBackground
    case controlBackground

    var nsColor: NSColor {
        switch self {
        case .textBackground:
            return .textBackgroundColor
        case .windowBackground:
            return .windowBackgroundColor
        case .controlBackground:
            return .controlBackgroundColor
        }
    }
}

enum AppSurfacePalette {
    static func semanticColor(for role: AppSurfaceRole, appearance: AppSurfaceAppearance) -> AppSurfaceSemanticColor {
        switch appearance {
        case .light:
            switch role {
            case .canvas, .surface:
                return .textBackground
            case .sidebar:
                return .windowBackground
            }
        case .dark:
            switch role {
            case .canvas, .sidebar:
                return .windowBackground
            case .surface:
                return .controlBackground
            }
        }
    }

    static func nsColor(for role: AppSurfaceRole, appearance: AppSurfaceAppearance) -> NSColor {
        semanticColor(for: role, appearance: appearance).nsColor
    }

    static func opacity(for role: AppSurfaceRole, appearance: AppSurfaceAppearance) -> Double {
        switch appearance {
        case .light:
            return 1.0
        case .dark:
            switch role {
            case .canvas:
                return 1.0
            case .sidebar:
                return 0.92
            case .surface:
                return 0.78
            }
        }
    }

    static func tintOpacity(isActive: Bool, appearance: AppSurfaceAppearance) -> Double {
        switch appearance {
        case .light:
            return isActive ? 0.045 : 0.015
        case .dark:
            return isActive ? 0.08 : 0.035
        }
    }

    static func shadowOpacity(isActive: Bool, appearance: AppSurfaceAppearance) -> Double {
        switch appearance {
        case .light:
            return isActive ? 0.08 : 0.025
        case .dark:
            return isActive ? 0.10 : 0.03
        }
    }
}
