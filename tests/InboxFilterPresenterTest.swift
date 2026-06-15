import Foundation

@main
struct InboxFilterPresenterTest {
    static func main() {
        let items = [
            InboxItem(kind: .upgradeDecision, severity: .warning, title: "Risk", summary: "Needs confirmation"),
            InboxItem(kind: .sourceIssue, severity: .warning, title: "Source", summary: "Homebrew missing"),
            InboxItem(kind: .permissionIssue, severity: .critical, title: "Permission", summary: "Permission denied"),
            InboxItem(kind: .appUpdate, severity: .info, title: "App", summary: "Update available")
        ]

        precondition(InboxFilterPresenter.items(from: items, kind: .all, severity: .all).count == 4)

        let permissionItems = InboxFilterPresenter.items(from: items, kind: .permissions, severity: .all)
        precondition(permissionItems.map(\.kind) == [.permissionIssue])

        let sourceWarnings = InboxFilterPresenter.items(from: items, kind: .sources, severity: .warning)
        precondition(sourceWarnings.map(\.kind) == [.sourceIssue])

        let criticalItems = InboxFilterPresenter.items(from: items, kind: .all, severity: .critical)
        precondition(criticalItems.map(\.kind) == [.permissionIssue])
    }
}
