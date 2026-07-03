import AppKit
import SwiftUI

enum AppChromeLayout {
    static let topRailHeight: CGFloat = 72
    static let sidebarTopPadding: CGFloat = 34
    static let detailHeaderTopPadding: CGFloat = 34
}

enum AppWindowChromePolicy {
    static let usesFullSizeContentView = true
    static let hidesNativeTitle = true
    static let titlebarAppearsTransparent = true
    static let removesAutomaticSidebarToggle = true

    static func apply(to window: NSWindow) {
        if usesFullSizeContentView {
            window.styleMask.insert(.fullSizeContentView)
        }
        if hidesNativeTitle {
            window.titleVisibility = .hidden
        }
        window.titlebarAppearsTransparent = titlebarAppearsTransparent
        if removesAutomaticSidebarToggle {
            removeAutomaticSidebarToggle(from: window.toolbar)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak window] in
                removeAutomaticSidebarToggle(from: window?.toolbar)
            }
        }
        window.isMovableByWindowBackground = true
    }

    private static func removeAutomaticSidebarToggle(from toolbar: NSToolbar?) {
        guard let toolbar else { return }
        for (index, item) in toolbar.items.enumerated().reversed() where isAutomaticSidebarToggle(item) {
            toolbar.removeItem(at: index)
        }
    }

    private static func isAutomaticSidebarToggle(_ item: NSToolbarItem) -> Bool {
        item.itemIdentifier == .toggleSidebar ||
            item.itemIdentifier.rawValue.localizedCaseInsensitiveContains("sidebar")
    }
}

struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        applyChromeWhenAvailable(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyChromeWhenAvailable(from: nsView)
    }

    private func applyChromeWhenAvailable(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            AppWindowChromePolicy.apply(to: window)
        }
    }
}
