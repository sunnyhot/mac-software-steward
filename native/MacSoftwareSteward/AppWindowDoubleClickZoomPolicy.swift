import CoreGraphics

enum AppWindowDoubleClickZoomPolicy {
    static func shouldZoomOnDoubleClick(
        clickCount: Int,
        windowLocationY: CGFloat,
        contentHeight: CGFloat
    ) -> Bool {
        clickCount >= 2 && contentHeight > 0 && windowLocationY >= contentHeight
    }
}
