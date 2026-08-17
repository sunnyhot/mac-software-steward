import Foundation

@main
struct HomebrewCaskUpdateAdvisorTest {
    static func main() async {
        let missingAppPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-clash-party-\(UUID().uuidString).app")
            .path
        let metadataJSON = """
        {
          "casks": [
            {
              "token": "clash-party",
              "version": "1.9.6",
              "url": "https://github.com/mihomo-party-org/clash-party/releases/download/v1.9.6/clash-party-macos-1.9.6-arm64.pkg",
              "url_specs": {
                "verified": "github.com/mihomo-party-org/clash-party/"
              },
              "homepage": "https://clashparty.org/",
              "auto_updates": true,
              "artifacts": [
                {
                  "app": ["Clash Party.app"],
                  "target": "\(missingAppPath)"
                }
              ]
            }
          ]
        }
        """

        let metadata = HomebrewCaskUpdateAdvisor.parseMetadata(from: metadataJSON)
        let clashParty = metadata["clash-party"]
        precondition(clashParty?.token == "clash-party")
        precondition(clashParty?.version == "1.9.6")
        precondition(clashParty?.autoUpdates == true)
        precondition(clashParty?.releaseFeedURLString == "https://github.com/mihomo-party-org/clash-party/releases.atom")
        precondition(clashParty?.appArtifactPaths == [missingAppPath])

        let atom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>v2.0.0</title>
          </entry>
          <entry>
            <title>v1.9.6</title>
          </entry>
        </feed>
        """
        precondition(HomebrewCaskUpdateAdvisor.parseLatestVersion(from: Data(atom.utf8)) == "2.0.0")

        let advisory = HomebrewCaskUpdateAdvisory(
            token: "clash-party",
            currentVersion: "2.0.0",
            sourceURLString: "https://github.com/mihomo-party-org/clash-party/releases/latest",
            diagnostic: "GitHub Releases 发现版本 2.0.0。"
        )
        let packages = SoftwareScanner.mergeBrew(
            installed: [(name: "clash-party", installedVersion: "1.9.6")],
            outdated: [],
            kind: "cask",
            caskMetadataByName: metadata,
            caskAdvisoriesByName: ["clash-party": advisory]
        )

        precondition(packages.count == 1)
        precondition(packages[0].name == "clash-party")
        precondition(packages[0].installedVersion == "1.9.6")
        precondition(packages[0].currentVersion == "2.0.0")
        precondition(packages[0].autoUpdates)
        precondition(packages[0].outdated)
        precondition(!packages[0].upgradeable)
        precondition(packages[0].manualUpdateOnly)
        precondition(packages[0].advisoryURLString == advisory.sourceURLString)
        precondition(packages[0].hasStaleInstallRecord)

        let installedTargetApp = AppItem(
            id: "/Applications/Clash Party.app",
            name: "clash-party",
            version: "2.0.0",
            availableVersion: "2.0.0",
            path: "/Applications/Clash Party.app",
            source: "Developer",
            obtainedFrom: "identified developer",
            architecture: "arm64",
            managedBy: "brew-cask",
            updateState: "outdated",
            relatedPackageID: packages[0].id
        )
        let reconciled = SoftwareScanner.reconcileManualCaskAdvisories(
            packages,
            applications: [installedTargetApp]
        )
        precondition(!reconciled[0].outdated)
        precondition(!reconciled[0].manualUpdateOnly)
        precondition(!reconciled[0].hasStaleInstallRecord)
        precondition(reconciled[0].installedVersion == "2.0.0")

        var channelPackage = packages[0]
        channelPackage.id = "brew:cask:clash-party@beta"
        channelPackage.name = "clash-party@beta"
        let unlinkedChannelApp = AppItem(
            id: installedTargetApp.id,
            name: "Clash Party",
            version: "2.0.0",
            availableVersion: "",
            path: installedTargetApp.path,
            source: installedTargetApp.source,
            obtainedFrom: installedTargetApp.obtainedFrom,
            architecture: installedTargetApp.architecture,
            managedBy: "manual",
            updateState: "unknown",
            relatedPackageID: ""
        )
        let reconciledChannel = SoftwareScanner.reconcileManualCaskAdvisories(
            [channelPackage],
            applications: [unlinkedChannelApp]
        )
        precondition(!reconciledChannel[0].outdated, "带 @channel 的 cask 应能匹配实际应用名")

        // 版本串归一化：渠道后缀段对齐（warp 这类 auto_updates cask 的常见差异）。
        precondition(SoftwareScanner.normalizedVersionString("0.2026.08.12.21.54.stable_00") == "0.2026.08.12.21.54.00")
        precondition(SoftwareScanner.normalizedVersionString("1.2.3.stable_01") == "1.2.3.01")
        precondition(SoftwareScanner.normalizedVersionString("1.2.3") == "1.2.3")
        precondition(SoftwareScanner.normalizedVersionString("2.0.0-beta_01") == "2.0.0-beta_01")

        // autoUpdates + outdated：应用已通过自带更新器升到目标版本（版本串渠道后缀不同），停止标记。
        let warpCask = BrewPackage(
            id: "brew:cask:warp",
            kind: "cask",
            name: "warp",
            installedVersion: "0.2026.08.05.09.03.stable_01",
            currentVersion: "0.2026.08.12.21.54.stable_00",
            pinned: false,
            autoUpdates: true,
            outdated: true,
            upgradeable: true
        )
        let warpApp = AppItem(
            id: "/Applications/Warp.app",
            name: "Warp",
            version: "0.2026.08.12.21.54.00",
            availableVersion: "",
            path: "/Applications/Warp.app",
            source: "Developer",
            obtainedFrom: "identified developer",
            architecture: "arm64",
            managedBy: "brew-cask",
            updateState: "outdated",
            relatedPackageID: warpCask.id
        )
        let reconciledWarp = SoftwareScanner.reconcileManualCaskAdvisories([warpCask], applications: [warpApp])
        precondition(!reconciledWarp[0].outdated, "应用已自更新到目标版本时，应停止标记 outdated")
        precondition(!reconciledWarp[0].upgradeable)
        precondition(reconciledWarp[0].installedVersion == "0.2026.08.12.21.54.00")

        // autoUpdates + outdated：应用仍低于目标版本，保持 outdated 交由 brew 升级。
        var olderWarpApp = warpApp
        olderWarpApp.version = "0.2026.08.05.09.03.01"
        let unreconciledWarp = SoftwareScanner.reconcileManualCaskAdvisories([warpCask], applications: [olderWarpApp])
        precondition(unreconciledWarp[0].outdated, "应用版本低于目标时应保持 outdated")
        precondition(unreconciledWarp[0].upgradeable)

        let hyper = UpdatablePackage.brew(BrewPackage(
            id: "brew:cask:hyper",
            kind: "cask",
            name: "hyper",
            installedVersion: "3.4.1",
            currentVersion: "4.0.0-canary.5",
            pinned: false,
            autoUpdates: true,
            outdated: true,
            upgradeable: false,
            manualUpdateOnly: true,
            advisoryURLString: "https://github.com/vercel/hyper/releases"
        ))
        let hyperResolution = ManualCaskUpdateResolver.resolution(for: hyper)
        precondition(hyperResolution?.kind == .switchChannel)
        precondition(hyperResolution?.targetCaskToken == "hyper@canary")
        precondition(hyperResolution?.actionTitle == "切换到 Canary")

        let thaw = UpdatablePackage.brew(BrewPackage(
            id: "brew:cask:thaw@beta",
            kind: "cask",
            name: "thaw@beta",
            installedVersion: "2.0.0-rc.1",
            currentVersion: "2.0.0-rc.2",
            pinned: false,
            autoUpdates: true,
            outdated: true,
            upgradeable: false,
            manualUpdateOnly: true,
            advisoryURLString: "https://github.com/thaw-app/Thaw/releases"
        ))
        precondition(ManualCaskUpdateResolver.resolution(for: thaw)?.kind == .openOfficialUpdate)

        let infoJSON = #"{"casks":[{"token":"hyper@canary","version":"4.0.0-canary.5"}]}"#
        precondition(
            ManualCaskUpdateResolver.caskVersion(fromBrewInfoJSON: infoJSON, token: "hyper@canary") == "4.0.0-canary.5"
        )
        precondition(ManualCaskUpdateResolver.versionsMatch("v4.0.0-canary.5", "4.0.0-canary.5"))

        let localOnly = await SoftwareScanner.caskUpdateAdvisories(
            installedCasks: [(name: "clash-party", installedVersion: "1.9.6")],
            outdated: [],
            metadataByName: metadata,
            networkPolicy: .localOnly,
            checker: { _, _ in
                preconditionFailure("localOnly must not call the advisory checker")
            }
        )
        precondition(localOnly.isEmpty)

        let declaredSources = await SoftwareScanner.caskUpdateAdvisories(
            installedCasks: [(name: "clash-party", installedVersion: "1.9.6")],
            outdated: [],
            metadataByName: metadata,
            networkPolicy: .declaredSourcesOnly,
            checker: { metadata, installedVersion in
                precondition(metadata.token == "clash-party")
                precondition(installedVersion == "1.9.6")
                return advisory
            }
        )
        precondition(declaredSources["clash-party"] == advisory)
    }
}
