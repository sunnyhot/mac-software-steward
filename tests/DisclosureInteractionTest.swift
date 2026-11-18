import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("native/MacSoftwareSteward/Views", isDirectory: true)

let sharedComponents = try String(
    contentsOf: root.appendingPathComponent("SharedComponents.swift"),
    encoding: .utf8
)
let settings = try String(
    contentsOf: root.appendingPathComponent("SettingsView.swift"),
    encoding: .utf8
)

precondition(!sharedComponents.contains("DisclosureGroup"), "高频诊断详情不应要求额外展开")
precondition(!settings.contains("DisclosureGroup"), "高级设置应使用整行可点击入口")
precondition(sharedComponents.contains("Label(\"错误详情\""), "来源错误应直接显示技术详情")
precondition(settings.contains("AutomaticMaintenanceRow()"), "设置页应提供统一的自动维护开关")
precondition(!settings.contains("showsAdvancedUpgradeOptions"), "不再保留旧的高级设置折叠逻辑")
