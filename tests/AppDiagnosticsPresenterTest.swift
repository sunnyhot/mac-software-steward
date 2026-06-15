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
                diagnostic: "Sparkle feed 发现版本 2.0。"
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

        let brokenFeed = AppItem(
            id: "app:/Applications/BrokenFeed.app",
            name: "BrokenFeed",
            version: "1.0",
            availableVersion: "",
            path: "/Applications/BrokenFeed.app",
            source: "Developer",
            obtainedFrom: "Identified Developer",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "checkable",
            relatedPackageID: "",
            updateCapability: AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: "https://example.com/broken.xml",
                installedVersion: "1.0",
                summary: "可通过 Sparkle 检查更新",
                diagnostic: "Sparkle feed HTTP 状态码 500。"
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

        let rows = AppDiagnosticsPresenter.rows(from: [sparkle, vendor, brokenFeed, quiet])
        precondition(rows.count == 4)

        precondition(rows[0].appID == sparkle.id)
        precondition(rows[0].appName == "Sparkle")
        precondition(rows[0].detectorTitle == "Sparkle")
        precondition(rows[0].stateTitle == "可更新")
        precondition(rows[0].reasonTitle == "发现新版本")
        precondition(rows[0].summary == "Sparkle 发现新版本 2.0")
        precondition(rows[0].diagnostic == "Sparkle feed 发现版本 2.0。")
        precondition(rows[0].feedURLString == "https://example.com/appcast.xml")
        precondition(rows[0].severity == .warning)
        precondition(rows[0].detailItems.contains(AppDiagnosticDetailItem(title: "安装版本", value: "1.0", symbol: "number")))
        precondition(rows[0].detailItems.contains(AppDiagnosticDetailItem(title: "可用版本", value: "2.0", symbol: "arrow.up.circle")))

        precondition(rows[1].appID == vendor.id)
        precondition(rows[1].detectorTitle == "Chrome Keystone")
        precondition(rows[1].stateTitle == "可检查")
        precondition(rows[1].reasonTitle == "无法确认版本")
        precondition(rows[1].diagnostic == "暂无诊断细节。")
        precondition(rows[1].actionHint.contains("打开应用"))
        precondition(rows[1].severity == .info)

        precondition(rows[2].appID == brokenFeed.id)
        precondition(rows[2].reasonTitle == "更新源异常")
        precondition(rows[2].actionHint.contains("更新源"))
        precondition(rows[2].severity == .warning)

        precondition(rows[3].appID == quiet.id)
        precondition(rows[3].reasonTitle == "无法确认版本")
        precondition(rows[3].summary == "未发现可执行更新器信息。")
        precondition(rows[3].detailItems.contains(AppDiagnosticDetailItem(title: "管理方式", value: "manual", symbol: "tag")))
    }
}
