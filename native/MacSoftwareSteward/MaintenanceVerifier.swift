import Foundation

// MARK: - Maintenance Verifier
//
// 封装现有 UpgradeVerifier 的重扫后校验行为，实现 MaintenanceVerifying 协议。
// 命令成功但版本仍 outdated → mismatch；包不在新扫描结果中 → notFound。
// 设计依据：docs/superpowers/specs/2026-07-10-unified-maintenance-engine-dashboard-design.md

struct MaintenanceVerifier: MaintenanceVerifying {
    func verify(executedPackageIDs: Set<String>, scan: ScanResult) async -> MaintenanceVerificationResult {
        let remainingOutdated = UpgradeVerifier.remainingOutdatedIDs(in: scan)
        let allScannedIDs = Set(
            scan.brew.formulae.map(\.id)
                + scan.brew.casks.map(\.id)
                + scan.mas.apps.map(\.id)
        )

        var verifications: [String: MaintenancePackageVerification] = [:]

        for packageID in executedPackageIDs {
            if !allScannedIDs.contains(packageID) {
                verifications[packageID] = MaintenancePackageVerification(
                    packageID: packageID,
                    status: .notFound,
                    detail: "包不在重新扫描结果中（可能已被移除）"
                )
            } else if remainingOutdated.contains(packageID) {
                verifications[packageID] = MaintenancePackageVerification(
                    packageID: packageID,
                    status: .mismatch,
                    detail: "命令成功，但版本仍为 outdated"
                )
            } else {
                verifications[packageID] = MaintenancePackageVerification(
                    packageID: packageID,
                    status: .verified,
                    detail: "升级完成，已验证"
                )
            }
        }

        return MaintenanceVerificationResult(verifications: verifications)
    }
}
