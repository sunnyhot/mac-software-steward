import Foundation

@MainActor
protocol SoftwareScanning {
    func scanAll(includeGreedy: Bool, onPhaseChange: ((ScanPhase) -> Void)?) async -> ScanResult
}

struct LiveSoftwareScanning: SoftwareScanning {
    nonisolated init() {}

    func scanAll(includeGreedy: Bool, onPhaseChange: ((ScanPhase) -> Void)?) async -> ScanResult {
        await SoftwareScanner.scanAll(includeGreedy: includeGreedy, onPhaseChange: onPhaseChange)
    }
}
