import Foundation

enum SettingsPageGroup: String, Equatable {
    case general = "通用"
    case appUpdates = "应用更新"

    var title: String {
        rawValue
    }

    var symbol: String {
        switch self {
        case .general:
            return "gearshape"
        case .appUpdates:
            return "arrow.down.app"
        }
    }
}
