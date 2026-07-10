import Foundation

@main
struct MaintenanceVerifierTest {
    static func main() async {
        let verifier = MaintenanceVerifier()

        // MARK: verified：包执行后不再 outdated
        let jq = BrewPackage(id: "brew:formula:jq", kind: "formula", name: "jq", installedVersion: "1.7", currentVersion: "1.7", pinned: false, autoUpdates: false, outdated: false, upgradeable: false)
        let verifiedScan = scanWith(formulae: [jq])
        let result1 = await verifier.verify(executedPackageIDs: ["brew:formula:jq"], scan: verifiedScan)
        precondition(result1.verifications["brew:formula:jq"]?.status == .verified, "不再 outdated 的包应 verified")
        precondition(result1.mismatchCount == 0, "无 mismatch")
        precondition(result1.notFoundCount == 0, "无 notFound")

        // MARK: mismatch：命令成功但仍 outdated
        let stillOutdated = BrewPackage(id: "brew:formula:jq", kind: "formula", name: "jq", installedVersion: "1.6", currentVersion: "1.7", pinned: false, autoUpdates: false, outdated: true, upgradeable: true)
        let mismatchScan = scanWith(formulae: [stillOutdated])
        let result2 = await verifier.verify(executedPackageIDs: ["brew:formula:jq"], scan: mismatchScan)
        precondition(result2.verifications["brew:formula:jq"]?.status == .mismatch, "仍 outdated 应 mismatch")
        precondition(result2.mismatchCount == 1, "有 1 个 mismatch")

        // MARK: notFound：包不在新扫描结果中
        let emptyScan = scanWith(formulae: [])
        let result3 = await verifier.verify(executedPackageIDs: ["brew:formula:gone"], scan: emptyScan)
        precondition(result3.verifications["brew:formula:gone"]?.status == .notFound, "不在扫描结果中应 notFound")
        precondition(result3.notFoundCount == 1, "有 1 个 notFound")

        // MARK: 空集合
        let result4 = await verifier.verify(executedPackageIDs: [], scan: verifiedScan)
        precondition(result4.verifications.isEmpty, "空执行集应产出空校验")

        print("MaintenanceVerifierTest passed")
    }

    private static func scanWith(formulae: [BrewPackage]) -> ScanResult {
        ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: formulae.count, brewCasks: 0, masApps: 0, outdated: formulae.filter(\.outdated).count, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew 5", error: "", includeGreedy: false, formulae: formulae, casks: []),
            mas: MasScan(available: false, path: "", error: "", apps: [])
        )
    }
}
