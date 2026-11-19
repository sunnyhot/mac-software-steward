import Foundation

/// 使用 macOS 原生标题栏双击行为，在放大与还原之间切换。
/// 仅写入当前应用的偏好域，不修改系统全局设置，也不拦截内容区事件。
enum WindowDoubleClickZoomPolicy {
    static let actionKey = "AppleActionOnDoubleClick"
    static let maximizeAction = "Maximize"

    static func enable(defaults: UserDefaults = .standard) {
        defaults.set(maximizeAction, forKey: actionKey)
    }
}
