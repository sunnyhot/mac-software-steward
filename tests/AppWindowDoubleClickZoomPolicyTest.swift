import Foundation

@main
struct AppWindowDoubleClickZoomPolicyTest {
    static func main() {
        precondition(
            AppWindowDoubleClickZoomPolicy.shouldZoomOnDoubleClick(
                clickCount: 2,
                windowLocationY: 721,
                contentHeight: 720
            ),
            "Double-clicking above the content area should zoom the window"
        )
        precondition(
            !AppWindowDoubleClickZoomPolicy.shouldZoomOnDoubleClick(
                clickCount: 1,
                windowLocationY: 721,
                contentHeight: 720
            ),
            "Single clicks must not zoom the window"
        )
        precondition(
            !AppWindowDoubleClickZoomPolicy.shouldZoomOnDoubleClick(
                clickCount: 2,
                windowLocationY: 700,
                contentHeight: 720
            ),
            "Double-clicks inside app content must not zoom the window"
        )
        precondition(
            !AppWindowDoubleClickZoomPolicy.shouldZoomOnDoubleClick(
                clickCount: 2,
                windowLocationY: 10,
                contentHeight: 0
            ),
            "A window without a measurable content area should not zoom"
        )
    }
}
