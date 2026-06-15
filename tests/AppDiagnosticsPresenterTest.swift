import Foundation

@main
struct AppDiagnosticsPresenterTest {
    static func main() {
        let sparkle = AppItem(
            id: "app:/Applications/Sparkle.app",
            name: "Sparkle",
            version: "1.0",
            availableVersion: "2.0",
            path: "/Applications/Sparkle.app",
            source: "Developer",
            obtainedFrom: "Identified Developer",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "outdated",
            relatedPackageID: "",
            updateCapability: AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: "https://example.com/appcast.xml",
                installedVersion: "1.0",
                summary: "Sparkle 发现新版本 2.0",
                diagnostic: "Sparkle feed HTTP 状态码 500。"
            )
        )

        let vendor = AppItem(
            id: "app:/Applications/Chrome.app",
            name: "Chrome",
            version: "126",
            availableVersion: "",
            path: "/Applications/Chrome.app",
            source: "Google",
            obtainedFrom: "Identified Developer",
            architecture: "universal",
            managedBy: "manual",
            updateState: "checkable",
            relatedPackageID: "",
            updateCapability: AppUpdateCapability(
                detector: .chromeKeystone,
                confidence: .high,
                feedURLString: "",
                installedVersion: "126",
                summary: "可通过 Chrome 内置更新器检查",
                diagnostic: ""
            )
        )

        let quiet = AppItem(
            id: "app:/Applications/Quiet.app",
            name: "Quiet",
            version: "1.0",
            availableVersion: "",
            path: "/Applications/Quiet.app",
            source: "Unknown",
            obtainedFrom: "",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "unknown",
            relatedPackageID: ""
        )

        let rows = AppDiagnosticsPresenter.rows(from: [sparkle, vendor, quiet])
        precondition(rows.count == 2)

        precondition(rows[0].appID == sparkle.id)
        precondition(rows[0].appName == "Sparkle")
        precondition(rows[0].detectorTitle == "Sparkle")
        precondition(rows[0].stateTitle == "可更新")
        precondition(rows[0].summary == "Sparkle 发现新版本 2.0")
        precondition(rows[0].diagnostic == "Sparkle feed HTTP 状态码 500。")
        precondition(rows[0].feedURLString == "https://example.com/appcast.xml")
        precondition(rows[0].severity == .warning)

        precondition(rows[1].appID == vendor.id)
        precondition(rows[1].detectorTitle == "Chrome Keystone")
        precondition(rows[1].stateTitle == "可检查")
        precondition(rows[1].diagnostic == "暂无诊断细节。")
        precondition(rows[1].severity == .info)

        precondition(AppDiagnosticsPresenter.row(from: quiet) == nil)
    }
}
