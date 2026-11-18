import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let model = try String(contentsOf: root.appendingPathComponent("native/MacSoftwareSteward/StewardModel.swift"), encoding: .utf8)
let executor = try String(contentsOf: root.appendingPathComponent("native/MacSoftwareSteward/MaintenanceExecutor.swift"), encoding: .utf8)
let shared = try String(contentsOf: root.appendingPathComponent("native/MacSoftwareSteward/Views/SharedComponents.swift"), encoding: .utf8)

precondition(model.contains("let knownIDs = Set(updateAttentionPackages.map"), "orphan filtering must exclude every visible package")
precondition(executor.contains("verifyCaskReceiptRemoved(brewPath: try? await requireCommand("), "receipt checks must resolve brew independently of rm")
precondition(executor.contains("var stepsToExecute"), "sudo cleanup must revalidate app presence before privileged execution")
precondition(executor.contains("CaskRecordCleanup.appReappearedExitCode"), "app reappearance must be a skip, not a false success")

let retryBody = executor.components(separatedBy: "    func retryPackage(").last ?? ""
let packageGuard = retryBody.range(of: "guard let package = availablePackages.first")
let removeFailure = retryBody.range(of: "packageProgress.removeValue(forKey: packageID)")
precondition(packageGuard != nil && removeFailure != nil)
precondition(packageGuard!.lowerBound < removeFailure!.lowerBound, "retry must not expose failed → nil → queued")

precondition(model.contains("recoveryAction == .reinstall"), "multi-version failures must route to explicit reinstall")
precondition(model.contains("has multiple installed versions"), "formula uninstall must be gated by brew list evidence")
precondition(model.contains("try HomebrewDownloadMonitor.removeIncompleteDownload("), "cache cleanup errors must not be silently ignored")
precondition(model.contains("下载缓存失败"), "cache cleanup failures must be surfaced to the user")

let lineBody = shared.components(separatedBy: "struct FlowingAccentLine").last?.components(separatedBy: "struct PolishedTaskSurfaceModifier").first ?? ""
precondition(!lineBody.contains("GeometryReader"), "progress accent line must not trigger layout feedback")
precondition(!lineBody.contains("withAnimation"), "progress accent line must not animate during row updates")
