import Foundation

@main
struct ScannerSparkleAppcastPolicyTest {
    static func main() async {
        let app = AppItem(
            id: "app:/Applications/Sparkle.app",
            name: "Sparkle",
            version: "1.0",
            availableVersion: "",
            path: "/Applications/Sparkle.app",
            source: "Developer",
            obtainedFrom: "Identified Developer",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "checkable",
            relatedPackageID: "",
            updateCapability: AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: "https://example.com/appcast.xml",
                installedVersion: "1.0",
                summary: "可通过 Sparkle 检查更新",
                diagnostic: ""
            )
        )

        let localOnly = await SoftwareScanner.enrichRegularAppUpdates(
            [app],
            networkPolicy: .localOnly,
            sparkleChecker: { _, _ in
                preconditionFailure("localOnly must not fetch Sparkle feeds")
            }
        )
        precondition(localOnly[0].availableVersion.isEmpty)
        precondition(localOnly[0].updateState == "checkable")

        let checked = await SoftwareScanner.enrichRegularAppUpdates(
            [app],
            networkPolicy: .declaredSourcesOnly,
            sparkleChecker: { feed, installed in
                precondition(feed == "https://example.com/appcast.xml")
                precondition(installed == "1.0")
                return SparkleAppcastCheckResult(availableVersion: "2.0", diagnostic: "ok")
            }
        )
        precondition(checked[0].availableVersion == "2.0")
        precondition(checked[0].updateState == "outdated")
        precondition(checked[0].updateCapability.diagnostic == "ok")
    }
}
