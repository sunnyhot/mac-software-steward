import Foundation

actor SparkleConcurrencyProbe {
    private var active = 0
    private var maximumActive = 0
    private var feeds: [String] = []

    func start(feed: String) {
        active += 1
        maximumActive = max(maximumActive, active)
        feeds.append(feed)
    }

    func finish() {
        active -= 1
    }

    func maxActive() -> Int { maximumActive }

    func observedFeeds() -> [String] { feeds }
}

@main
struct ScannerSparkleAppcastPolicyTest {
    static func main() async {
        let app = makeSparkleApp(
            name: "Sparkle",
            feed: "https://example.com/appcast.xml"
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
                return SparkleAppcastCheckResult(
                    availableVersion: "2.0",
                    diagnostic: "ok",
                    downloadURLString: "https://example.com/app.zip"
                )
            }
        )
        precondition(checked[0].availableVersion == "2.0")
        precondition(checked[0].updateState == "outdated")
        precondition(checked[0].updateCapability.diagnostic == "ok")
        precondition(checked[0].updateCapability.downloadURLString == "https://example.com/app.zip")

        let plain = AppItem(
            id: "app:/Applications/Plain.app",
            name: "Plain",
            version: "1.0",
            availableVersion: "",
            path: "/Applications/Plain.app",
            source: "Developer",
            obtainedFrom: "Identified Developer",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "unknown",
            relatedPackageID: "",
            updateCapability: .none
        )
        let apps = [
            makeSparkleApp(name: "One", feed: "https://example.com/one.xml"),
            plain,
            makeSparkleApp(name: "Two", feed: "https://example.com/two.xml"),
            makeSparkleApp(name: "Three", feed: "https://example.com/three.xml")
        ]
        let probe = SparkleConcurrencyProbe()
        let concurrent = await SoftwareScanner.enrichRegularAppUpdates(
            apps,
            networkPolicy: .declaredSourcesOnly,
            sparkleConcurrencyLimit: 2,
            sparkleChecker: { feed, _ in
                await probe.start(feed: feed)
                if feed.contains("one") {
                    try? await Task.sleep(for: .milliseconds(40))
                } else {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                await probe.finish()
                let name = feed
                    .replacingOccurrences(of: "https://example.com/", with: "")
                    .replacingOccurrences(of: ".xml", with: "")
                return SparkleAppcastCheckResult(availableVersion: "2.0-\(name)", diagnostic: "checked \(name)")
            }
        )

        let maxActive = await probe.maxActive()
        let observedFeeds = await probe.observedFeeds()
        precondition(maxActive == 2)
        let expectedFeeds = [
            "https://example.com/one.xml",
            "https://example.com/two.xml",
            "https://example.com/three.xml"
        ]
        precondition(observedFeeds.count == expectedFeeds.count)
        precondition(Set(observedFeeds) == Set(expectedFeeds))
        precondition(concurrent.map { $0.id } == apps.map { $0.id })
        precondition(concurrent[0].availableVersion == "2.0-one")
        precondition(concurrent[1].availableVersion.isEmpty)
        precondition(concurrent[2].availableVersion == "2.0-two")
        precondition(concurrent[3].availableVersion == "2.0-three")

        let clamped = await SoftwareScanner.enrichRegularAppUpdates(
            [apps[0], apps[2]],
            networkPolicy: .declaredSourcesOnly,
            sparkleConcurrencyLimit: 0,
            sparkleChecker: { _, _ in
                SparkleAppcastCheckResult(availableVersion: "2.0", diagnostic: "ok")
            }
        )
        precondition(clamped[0].availableVersion == "2.0")
        precondition(clamped[1].availableVersion == "2.0")
    }

    private static func makeSparkleApp(name: String, feed: String) -> AppItem {
        AppItem(
            id: "app:/Applications/\(name).app",
            name: name,
            version: "1.0",
            availableVersion: "",
            path: "/Applications/\(name).app",
            source: "Developer",
            obtainedFrom: "Identified Developer",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "checkable",
            relatedPackageID: "",
            updateCapability: AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: feed,
                installedVersion: "1.0",
                summary: "可通过 Sparkle 检查更新",
                diagnostic: ""
            )
        )
    }
}
