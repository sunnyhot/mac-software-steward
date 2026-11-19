import Foundation

@main
struct DailyInspectionRepairPolicyTest {
    static func main() {
        let helper = "/Applications/MacSoftwareSteward.app/Contents/MacOS/MacSoftwareStewardAgent"
        let healthy = makeConfig(helper: helper)
        precondition(DailyInspectionRepairPolicy.action(preferenceEnabled: false, config: healthy) == .uninstall)
        precondition(DailyInspectionRepairPolicy.action(preferenceEnabled: false, config: makeConfig(enabled: false, helper: helper)) == .none)
        precondition(DailyInspectionRepairPolicy.action(
            preferenceEnabled: false,
            config: makeConfig(enabled: false, helper: helper),
            isLoaded: true
        ) == .uninstall, "A missing plist must not hide a still-loaded agent")
        precondition(DailyInspectionRepairPolicy.action(preferenceEnabled: true, config: makeConfig(enabled: false, helper: helper)) == .restore)
        precondition(DailyInspectionRepairPolicy.action(preferenceEnabled: true, config: makeConfig(hour: 11, helper: helper)) == .normalize)
        precondition(DailyInspectionRepairPolicy.action(preferenceEnabled: true, config: makeConfig(includeGreedy: false, helper: helper)) == .normalize)
        precondition(DailyInspectionRepairPolicy.action(preferenceEnabled: true, config: makeConfig(runBrewUpdate: false, helper: helper)) == .normalize)
        precondition(DailyInspectionRepairPolicy.action(preferenceEnabled: true, config: healthy) == .repairExisting)
        precondition(DailyInspectionRepairPolicy.action(
            preferenceEnabled: true,
            config: makeConfig(hour: 8, helper: helper),
            expectedHour: 8
        ) == .repairExisting, "A saved custom time must not be normalized back to 09:00")
        precondition(DailyInspectionRepairPolicy.action(
            preferenceEnabled: true,
            config: healthy,
            expectedHour: 8
        ) == .normalize, "A different saved time should update the existing LaunchAgent")
        precondition(DailyInspectionRepairPolicy.action(
            preferenceEnabled: true,
            config: makeConfig(health: .needsRepair("not loaded"), helper: helper)
        ) == .repairExisting)
    }

    private static func makeConfig(
        enabled: Bool = true,
        hour: Int = 9,
        includeGreedy: Bool = true,
        runBrewUpdate: Bool = true,
        health: DailyInspectionHealth = .healthy,
        helper: String
    ) -> DailyInspectionConfig {
        DailyInspectionConfig(
            enabled: enabled,
            hour: hour,
            minute: 0,
            includeGreedy: includeGreedy,
            runBrewUpdate: runBrewUpdate,
            installedHelperPath: helper,
            health: health,
            launchAgentPath: "/tmp/daily.plist",
            logPath: "/tmp/daily.log"
        )
    }
}
