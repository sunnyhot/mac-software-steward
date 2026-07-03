import Foundation

@main
struct AppWindowChromePolicyTest {
    static func main() {
        precondition(
            AppWindowChromePolicy.usesFullSizeContentView,
            "Main window content should extend into the native titlebar area"
        )
        precondition(
            AppWindowChromePolicy.hidesNativeTitle,
            "The native title should be hidden because the app renders its own header"
        )
        precondition(
            AppWindowChromePolicy.titlebarAppearsTransparent,
            "The titlebar should be transparent so it does not create a second header band"
        )
        precondition(
            AppWindowChromePolicy.removesAutomaticSidebarToggle,
            "The automatic sidebar toggle should not create a stray toolbar control in the header"
        )
        precondition(
            AppChromeLayout.sidebarTopPadding == AppChromeLayout.detailHeaderTopPadding,
            "Sidebar and detail header should share the same top rhythm"
        )
        precondition(
            AppChromeLayout.topRailHeight >= AppChromeLayout.detailHeaderTopPadding,
            "The unified rail should cover the aligned header spacing"
        )
    }
}
