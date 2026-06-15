import Foundation

@main
struct SourceIssueInboxFactoryTest {
    static func main() {
        let missingBrewScan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 0, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: false, path: "", prefix: "", version: "", error: "brew not found", includeGreedy: false, formulae: [], casks: []),
            mas: MasScan(available: true, path: "/opt/homebrew/bin/mas", error: "", apps: [])
        )
        let missingBrewItems = SourceIssueInboxFactory.items(from: missingBrewScan)
        precondition(missingBrewItems.count == 1)
        precondition(missingBrewItems[0].kind == .sourceIssue)
        precondition(missingBrewItems[0].severity == .warning)
        precondition(missingBrewItems[0].sourceID == "source:homebrew")
        precondition(missingBrewItems[0].title == "Homebrew 来源需要处理")
        precondition(missingBrewItems[0].actions.map(\.kind) == [.openSources, .rescan])

        let masUnavailableScan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 0, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew", error: "", includeGreedy: false, formulae: [], casks: []),
            mas: MasScan(available: false, path: "", error: "mas not found", apps: [])
        )
        let masItems = SourceIssueInboxFactory.items(from: masUnavailableScan)
        precondition(masItems.count == 1)
        precondition(masItems[0].severity == .info)
        precondition(masItems[0].sourceID == "source:mas")
        precondition(masItems[0].summary.contains("App Store"))

        let healthyScan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 0, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew", error: "", includeGreedy: false, formulae: [], casks: []),
            mas: MasScan(available: true, path: "/opt/homebrew/bin/mas", error: "", apps: [])
        )
        precondition(SourceIssueInboxFactory.items(from: healthyScan).isEmpty)
    }
}
