import Foundation

enum UpgradeVerifier {
    static func remainingOutdatedIDs(in result: ScanResult) -> Set<String> {
        Set(
            result.brew.formulae.filter(\.outdated).map(\.id)
                + result.brew.casks.filter(\.outdated).map(\.id)
                + result.mas.apps.filter(\.outdated).map(\.id)
        )
    }

    static func verify(
        progress: PackageUpgradeProgress,
        remainingPackageIDs: Set<String>
    ) -> PackageUpgradeProgress {
        guard progress.status == .succeeded else { return progress }
        var next = progress
        if remainingPackageIDs.contains(progress.packageID) {
            next.status = .warning
            next.detail = "命令成功，状态未确认"
            next.recoverySuggestion = "请重新扫描，或在终端中手动检查该软件是否仍可升级。"
        } else {
            next.detail = "升级完成，已验证"
        }
        next.updatedAt = Date()
        return next
    }
}
