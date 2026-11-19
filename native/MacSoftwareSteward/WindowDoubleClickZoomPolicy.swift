import AppKit
import Foundation

struct TitlebarZoomGeometry {
    static func shouldZoom(
        clickCount: Int,
        location: CGPoint,
        contentLayoutRect: CGRect,
        hitViewIsControl: Bool
    ) -> Bool {
        clickCount == 2
            && location.y >= contentLayoutRect.height
            && !hitViewIsControl
    }
}

/// 只处理标题栏空白区域的双击，避免 SwiftUI 窗口没有稳定执行系统默认行为。
enum WindowDoubleClickZoomPolicy {
    static let actionKey = "AppleActionOnDoubleClick"

    static func install() {
        // 旧版本用 Maximize 偏好尝试实现过此功能，关闭原生处理以免切换两次。
        UserDefaults.standard.set("None", forKey: actionKey)
        TitlebarDoubleClickZoomController.shared.install()
    }
}

private final class TitlebarDoubleClickZoomController: NSObject {
    static let shared = TitlebarDoubleClickZoomController()
    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.clickCount == 2,
                  let window = event.window,
                  window.styleMask.contains(.titled) else { return event }

            let location = event.locationInWindow
            let hitView = window.contentView?.hitTest(location)
            let isControl = hitView.map(Self.isInteractiveControl) ?? false
            guard TitlebarZoomGeometry.shouldZoom(
                clickCount: event.clickCount,
                location: location,
                contentLayoutRect: window.contentLayoutRect,
                hitViewIsControl: isControl
            ) else { return event }

            window.zoom(nil)
            return nil
        }
    }

    private static func isInteractiveControl(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let view = current {
            if view is NSButton || view is NSSegmentedControl || view is NSPopUpButton {
                return true
            }
            current = view.superview
        }
        return false
    }
}
