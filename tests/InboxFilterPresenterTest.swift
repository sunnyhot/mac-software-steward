import Foundation

@main
struct InboxFilterPresenterTest {
    static func main() {
        let items = [
            InboxItem(kind: .upgradeDecision, severity: .warning, title: "Risk", summary: "Needs confirmation", status: .pending),
            InboxItem(kind: .sourceIssue, severity: .warning, title: "Source", summary: "Homebrew missing", status: .resolved),
            InboxItem(kind: .permissionIssue, severity: .critical, title: "Permission", summary: "Permission denied", status: .ignored),
            InboxItem(kind: .appUpdate, severity: .info, title: "App", summary: "Update available", status: .pending)
        ]

        precondition(InboxFilterPresenter.items(from: items, kind: .all, severity: .all).count == 4)

        let permissionItems = InboxFilterPresenter.items(from: items, kind: .permissions, severity: .all)
        precondition(permissionItems.map(\.kind) == [.permissionIssue])

        let sourceWarnings = InboxFilterPresenter.items(from: items, kind: .sources, severity: .warning)
        precondition(sourceWarnings.map(\.kind) == [.sourceIssue])

        let criticalItems = InboxFilterPresenter.items(from: items, kind: .all, severity: .critical)
        precondition(criticalItems.map(\.kind) == [.permissionIssue])

        let pendingItems = InboxFilterPresenter.items(from: items, kind: .all, severity: .all, status: .pending)
        precondition(pendingItems.map(\.title) == ["Risk", "App"])

        let resolvedItems = InboxFilterPresenter.items(from: items, kind: .all, severity: .all, status: .resolved)
        precondition(resolvedItems.map(\.kind) == [.sourceIssue])

        let ignoredPermissions = InboxFilterPresenter.items(from: items, kind: .permissions, severity: .all, status: .ignored)
        precondition(ignoredPermissions.map(\.kind) == [.permissionIssue])

        let allStatusItems = InboxFilterPresenter.items(from: items, kind: .all, severity: .all, status: .all)
        precondition(allStatusItems.count == 4)
    }
}
