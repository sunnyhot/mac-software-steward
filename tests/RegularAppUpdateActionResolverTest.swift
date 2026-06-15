import Foundation

@main
struct RegularAppUpdateActionResolverTest {
    static func main() {
        let microsoft = RegularAppUpdateActionResolver.updaterPathCandidates(for: .microsoftAutoUpdate)
        precondition(microsoft.contains("/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app"))

        let adobe = RegularAppUpdateActionResolver.updaterPathCandidates(for: .adobeUpdater)
        precondition(adobe.contains("/Applications/Utilities/Adobe Creative Cloud/ACC/Creative Cloud.app"))

        let jetBrains = RegularAppUpdateActionResolver.updaterPathCandidates(for: .jetBrainsToolbox)
        precondition(jetBrains.contains("/Applications/JetBrains Toolbox.app"))

        precondition(RegularAppUpdateActionResolver.updaterPathCandidates(for: .sparkle).isEmpty)
    }
}
