import Foundation

@MainActor
final class DelayedScanner: SoftwareScanning {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func scanAll(includeGreedy: Bool, onPhaseChange: ((ScanPhase) -> Void)?) async -> ScanResult {
        callCount += 1
        onPhaseChange?(.brewInfo)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: includeGreedy,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 0, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: false, path: "", prefix: "", version: "", error: "", includeGreedy: includeGreedy, formulae: [], casks: []),
            mas: MasScan(available: false, path: "", error: "", apps: [])
        )
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@main
struct StewardModelScanGuardTest {
    @MainActor
    static func main() async {
        UserDefaults.standard.removeObject(forKey: "maxConcurrentUpgrades")

        let scanner = DelayedScanner()
        let model = StewardModel(scanner: scanner)

        let first = Task { await model.scanSoftware() }

        while scanner.callCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        await model.scanSoftware()

        let callsWhileRunning = scanner.callCount
        precondition(callsWhileRunning == 1, "Expected duplicate scan call to be ignored, got \(callsWhileRunning)")

        scanner.finish()
        await first.value

        precondition(model.isScanning == false, "Expected scan flag to reset after completion")
    }
}
