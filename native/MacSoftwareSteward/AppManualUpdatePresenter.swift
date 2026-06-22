import Foundation

struct AppManualUpdatePresentation: Equatable {
    var statusTitle: String?
    var primaryAction: AppUpdateAction?
    var primaryTitle: String
    var guidanceText: String
    var secondaryActions: [AppUpdateAction]
}

enum AppManualUpdatePresenter {
    static func presentation(for app: AppItem) -> AppManualUpdatePresentation {
        let actions = app.managedBy == "manual" ? actions(for: app) : []
        let primaryAction = actions.first { $0.kind == .openUpdater }
            ?? actions.first { $0.kind == .openApp }

        return AppManualUpdatePresentation(
            statusTitle: statusTitle(for: app),
            primaryAction: primaryAction,
            primaryTitle: primaryTitle(for: primaryAction, app: app),
            guidanceText: guidanceText(for: app, primaryAction: primaryAction),
            secondaryActions: secondaryActions(from: actions, primaryAction: primaryAction)
        )
    }

    private static func statusTitle(for app: AppItem) -> String? {
        switch app.updateState {
        case "outdated":
            return "需手动更新"
        case "checkable":
            return "可手动检查"
        default:
            return nil
        }
    }

    private static func primaryTitle(for action: AppUpdateAction?, app: AppItem) -> String {
        guard let action else { return "" }
        switch action.kind {
        case .openUpdater:
            return "打开更新器"
        case .openApp:
            return app.updateState == "outdated" ? "打开应用更新" : "打开应用检查"
        case .revealInFinder:
            return "在 Finder 中显示"
        case .directReplace:
            return "直接替换（风险自负）"
        }
    }

    private static func guidanceText(for app: AppItem, primaryAction: AppUpdateAction?) -> String {
        if hasDirectReplacementOption(app) {
            return "下一步：优先打开应用更新；也可选择直接替换，风险自负。"
        }
        guard let primaryAction else {
            return "下一步：在 Finder 中定位应用，打开后进入应用菜单手动确认版本。"
        }
        switch primaryAction.kind {
        case .openUpdater:
            return "下一步：打开更新器，确认是否有新版本。"
        case .openApp:
            return app.updateState == "outdated"
                ? "下一步：打开应用更新，按应用内提示完成升级。"
                : "下一步：打开应用检查，使用应用内更新入口确认版本。"
        case .revealInFinder:
            return "下一步：在 Finder 中定位应用，打开后进入应用菜单手动确认版本。"
        case .directReplace:
            return "下一步：直接替换会下载并覆盖当前 App，请确认风险后继续。"
        }
    }

    private static func actions(for app: AppItem) -> [AppUpdateAction] {
        var actions = app.updateCapability.actions
        if hasDirectReplacementOption(app),
           !actions.contains(where: { $0.kind == .directReplace }) {
            let directReplaceAction = AppUpdateAction(
                kind: .directReplace,
                title: "直接替换（风险自负）",
                systemImage: "exclamationmark.triangle"
            )
            if let finderIndex = actions.firstIndex(where: { $0.kind == .revealInFinder }) {
                actions.insert(directReplaceAction, at: finderIndex)
            } else {
                actions.append(directReplaceAction)
            }
        }
        return actions
    }

    private static func hasDirectReplacementOption(_ app: AppItem) -> Bool {
        app.updateState == "outdated"
            && app.updateCapability.detector == .sparkle
            && !(app.updateCapability.downloadURLString ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func secondaryActions(
        from actions: [AppUpdateAction],
        primaryAction: AppUpdateAction?
    ) -> [AppUpdateAction] {
        actions.filter { action in
            action != primaryAction
        }
    }
}
