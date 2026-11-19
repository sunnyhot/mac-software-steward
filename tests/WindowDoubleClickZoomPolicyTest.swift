import AppKit
import Foundation

@main
struct WindowDoubleClickZoomPolicyTest {
    static func main() throws {
        let contentRect = CGRect(x: 0, y: 0, width: 900, height: 600)
        precondition(
            TitlebarZoomGeometry.shouldZoom(
                clickCount: 2,
                location: CGPoint(x: 450, y: 630),
                contentLayoutRect: contentRect,
                hitViewIsControl: false
            ),
            "A titlebar double-click should zoom"
        )
        precondition(
            !TitlebarZoomGeometry.shouldZoom(
                clickCount: 1,
                location: CGPoint(x: 450, y: 630),
                contentLayoutRect: contentRect,
                hitViewIsControl: false
            ),
            "A single click must not zoom"
        )
        precondition(
            !TitlebarZoomGeometry.shouldZoom(
                clickCount: 2,
                location: CGPoint(x: 450, y: 500),
                contentLayoutRect: contentRect,
                hitViewIsControl: false
            ),
            "Content double-clicks must not zoom"
        )
        precondition(
            !TitlebarZoomGeometry.shouldZoom(
                clickCount: 2,
                location: CGPoint(x: 450, y: 630),
                contentLayoutRect: contentRect,
                hitViewIsControl: true
            ),
            "Titlebar buttons must keep their own behavior"
        )

        let appSource = try String(
            contentsOfFile: "native/MacSoftwareSteward/App.swift",
            encoding: .utf8
        )
        precondition(appSource.contains("applicationWillFinishLaunching"))
        precondition(appSource.contains("WindowDoubleClickZoomPolicy.install()"))
        precondition(!appSource.contains("onTapGesture(count: 2)"))
    }
}
