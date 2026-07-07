import Foundation

@main
struct HomebrewCaskUpdateAdvisorTest {
    static func main() async {
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
              "auto_updates": true
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
