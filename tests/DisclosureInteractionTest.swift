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
precondition(settings.contains("@AppStorage(\"advancedUpgradeOptionsExpanded\")"), "高级设置展开状态应持久保存")
precondition(settings.contains(".contentShape(Rectangle())"), "高级设置标题整行都应可点击")
