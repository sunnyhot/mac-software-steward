import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("native/MacSoftwareSteward", isDirectory: true)

let model = try String(contentsOf: root.appendingPathComponent("StewardModel.swift"), encoding: .utf8)
let content = try String(contentsOf: root.appendingPathComponent("ContentView.swift"), encoding: .utf8)
let applications = try String(contentsOf: root.appendingPathComponent("Views/ApplicationsView.swift"), encoding: .utf8)

precondition(!model.contains("@Published var query"), "即时搜索文本不应放在全局维护模型中")
precondition(model.contains("localSoftwareRows"), "本机软件展示行应在扫描完成后缓存")
precondition(content.contains("StewardSearchField"), "搜索输入应由独立组件维护")
precondition(content.contains("focusStewardSearch"), "搜索应支持 Command-F 聚焦")
precondition(applications.contains("model.localSoftwareRows"), "本机软件页应复用缓存展示行")
precondition(applications.contains("displayedRows"), "筛选结果应缓存，避免进度刷新时重复计算")
precondition(!applications.contains(".regularMaterial"), "长列表行不应逐项使用实时材质")
precondition(!applications.contains("scaleEffect(isHovered"), "长列表悬停不应触发逐行缩放合成")
