import Foundation

@MainActor
protocol SoftwareScanning {
    func scanAll(
        includeGreedy: Bool,
        regularAppNetworkPolicy: RegularAppNetworkPolicy,
        onPhaseChange: ((ScanPhase) -> Void)?
    ) async -> ScanResult
}

struct LiveSoftwareScanning: SoftwareScanning {
    nonisolated init() {}

    func scanAll(
        includeGreedy: Bool,
        regularAppNetworkPolicy: RegularAppNetworkPolicy = .declaredSourcesOnly,
        onPhaseChange: ((ScanPhase) -> Void)? = nil
    ) async -> ScanResult {
        await SoftwareScanner.scanAll(
            includeGreedy: includeGreedy,
            regularAppNetworkPolicy: regularAppNetworkPolicy,
            onPhaseChange: onPhaseChange
        )
    }
}
