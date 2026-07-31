# Automation Steward M1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first shippable slice of the automation steward experience: local automation profile persistence, inbox persistence, default/advanced navigation, a usable inbox screen, and settings controls.

**Architecture:** Add small local stores for automation profile and inbox data, keep `StewardModel` focused on existing scanning/upgrading, and gate detailed pages from `ContentView` through `AutomationProfileStore`. The M1 UI is a real shell for the future automation model: default mode starts on `InboxView`, advanced mode exposes the existing detailed console pages.

**Tech Stack:** Swift 5, SwiftUI, Combine, Foundation JSON persistence, existing `swiftc` scripts, existing single-file Swift tests.

---

## Scope Check

The approved design covers six independent milestones. This plan implements only M1:

- Automation profile model and store.
- Inbox item model and store.
- Default/advanced navigation split.
- Inbox, history and settings shell for M1.
- Native tests and script wiring for the new pure logic.

Risk assessment, notification delivery, ordinary `.app` update discovery, inspection reports and auto repair are not part of this M1 plan.

## File Structure

- Create `native/MacSoftwareSteward/AutomationProfileStore.swift`: local-only profile models and JSON store.
- Create `native/MacSoftwareSteward/InboxStore.swift`: local-only inbox models and JSON store.
- Create `native/MacSoftwareSteward/Views/InboxView.swift`: default landing page for pending user actions and onboarding prompt.
- Create `native/MacSoftwareSteward/Views/HistoryView.swift`: default-mode history view backed by existing `UpgradeHistoryStore`.
- Modify `native/MacSoftwareSteward/Models.swift`: add `inbox`, `history`, and `AppTab.visibleTabs(advancedModeEnabled:)`.
- Modify `native/MacSoftwareSteward/StewardModel.swift`: default selected tab becomes `.inbox`.
- Modify `native/MacSoftwareSteward/App.swift`: instantiate and inject `AutomationProfileStore` and `InboxStore`.
- Modify `native/MacSoftwareSteward/ContentView.swift`: list visible tabs based on advanced mode and route new pages.
- Modify `native/MacSoftwareSteward/Views/SettingsView.swift`: add automation profile and advanced mode controls.
- Modify `scripts/test-native.sh`: add the three new test executables.
- Create `tests/AutomationProfileStoreTest.swift`.
- Create `tests/InboxStoreTest.swift`.
- Create `tests/AppTabVisibilityTest.swift`.

---

### Task 1: Automation Profile Store

**Files:**
- Create: `native/MacSoftwareSteward/AutomationProfileStore.swift`
- Test: `tests/AutomationProfileStoreTest.swift`

- [ ] **Step 1: Write the failing test**

Create `tests/AutomationProfileStoreTest.swift`:

```swift
import Foundation

@main
struct AutomationProfileStoreTest {
    static func main() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("automation-profile-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = AutomationProfileStore(fileURL: url)
        precondition(store.profile == .manualDefault)
        precondition(store.profile.onboardingCompleted == false)
        precondition(store.profile.automationEnabled == false)
        precondition(store.profile.advancedModeEnabled == false)
        precondition(store.profile.notificationPolicy == .decisionsAndFailures)
        precondition(store.profile.regularAppNetworkPolicy == .declaredSourcesOnly)
        precondition(store.profile.autoRepairPolicy == .manualOnly)

        store.completeOnboarding(enableAutomation: true)
        precondition(store.profile.onboardingCompleted == true)
        precondition(store.profile.automationEnabled == true)
        precondition(store.profile.dailyInspectionEnabled == true)
        precondition(store.profile.lowRiskAutoUpgradeEnabled == true)

        store.setAdvancedMode(true)
        store.setNotificationPolicy(.everyInspection)
        store.setRegularAppNetworkPolicy(.localOnly)
        store.setAutoRepairPolicy(.allowLowRisk)

        let reloaded = AutomationProfileStore(fileURL: url)
        precondition(reloaded.profile.onboardingCompleted == true)
        precondition(reloaded.profile.automationEnabled == true)
        precondition(reloaded.profile.advancedModeEnabled == true)
        precondition(reloaded.profile.notificationPolicy == .everyInspection)
        precondition(reloaded.profile.regularAppNetworkPolicy == .localOnly)
        precondition(reloaded.profile.autoRepairPolicy == .allowLowRisk)

        reloaded.setAutomationEnabled(false)
        precondition(reloaded.profile.automationEnabled == false)
        precondition(reloaded.profile.lowRiskAutoUpgradeEnabled == false)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  tests/AutomationProfileStoreTest.swift \
  -o build/AutomationProfileStoreTest
```

Expected: FAIL with errors like `cannot find 'AutomationProfileStore' in scope`.

- [ ] **Step 3: Add the automation profile store**

Create `native/MacSoftwareSteward/AutomationProfileStore.swift`:

```swift
import Combine
import Foundation

enum NotificationPolicy: String, Codable, CaseIterable, Identifiable {
    case decisionsAndFailures
    case everyInspection
    case everyAction
    case silent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .decisionsAndFailures: return "只在需要处理时通知"
        case .everyInspection: return "每次巡检后通知"
        case .everyAction: return "每个动作都通知"
        case .silent: return "静默记录"
        }
    }
}

enum RegularAppNetworkPolicy: String, Codable, CaseIterable, Identifiable {
    case declaredSourcesOnly
    case aggressive
    case localOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .declaredSourcesOnly: return "声明来源与受控接口"
        case .aggressive: return "积极检查公开页面"
        case .localOnly: return "仅本地识别"
        }
    }
}

enum AutoRepairPolicy: String, Codable, CaseIterable, Identifiable {
    case manualOnly
    case allowLowRisk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manualOnly: return "手动确认"
        case .allowLowRisk: return "允许低风险自动修复"
        }
    }
}

struct AutomationProfile: Codable, Equatable {
    var onboardingCompleted: Bool
    var automationEnabled: Bool
    var dailyInspectionEnabled: Bool
    var lowRiskAutoUpgradeEnabled: Bool
    var advancedModeEnabled: Bool
    var notificationPolicy: NotificationPolicy
    var regularAppNetworkPolicy: RegularAppNetworkPolicy
    var autoRepairPolicy: AutoRepairPolicy

    static let manualDefault = AutomationProfile(
        onboardingCompleted: false,
        automationEnabled: false,
        dailyInspectionEnabled: false,
        lowRiskAutoUpgradeEnabled: false,
        advancedModeEnabled: false,
        notificationPolicy: .decisionsAndFailures,
        regularAppNetworkPolicy: .declaredSourcesOnly,
        autoRepairPolicy: .manualOnly
    )
}

final class AutomationProfileStore: ObservableObject {
    static let defaultFileURL: URL = {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)

        return baseURL
            .appendingPathComponent("MacSoftwareSteward", isDirectory: true)
            .appendingPathComponent("automation-profile.json")
    }()

    @Published private(set) var profile: AutomationProfile

    private let fileURL: URL

    init(fileURL: URL = AutomationProfileStore.defaultFileURL) {
        self.fileURL = fileURL
        profile = Self.load(from: fileURL)
    }

    func completeOnboarding(enableAutomation: Bool) {
        profile.onboardingCompleted = true
        profile.automationEnabled = enableAutomation
        profile.dailyInspectionEnabled = enableAutomation
        profile.lowRiskAutoUpgradeEnabled = enableAutomation
        save()
    }

    func setAutomationEnabled(_ enabled: Bool) {
        profile.automationEnabled = enabled
        if !enabled {
            profile.lowRiskAutoUpgradeEnabled = false
        }
        save()
    }

    func setDailyInspectionEnabled(_ enabled: Bool) {
        profile.dailyInspectionEnabled = enabled
        save()
    }

    func setLowRiskAutoUpgradeEnabled(_ enabled: Bool) {
        profile.lowRiskAutoUpgradeEnabled = enabled
        if enabled {
            profile.automationEnabled = true
        }
        save()
    }

    func setAdvancedMode(_ enabled: Bool) {
        profile.advancedModeEnabled = enabled
        save()
    }

    func setNotificationPolicy(_ policy: NotificationPolicy) {
        profile.notificationPolicy = policy
        save()
    }

    func setRegularAppNetworkPolicy(_ policy: RegularAppNetworkPolicy) {
        profile.regularAppNetworkPolicy = policy
        save()
    }

    func setAutoRepairPolicy(_ policy: AutoRepairPolicy) {
        profile.autoRepairPolicy = policy
        save()
    }

    private static func load(from fileURL: URL) -> AutomationProfile {
        guard let data = try? Data(contentsOf: fileURL) else {
            return .manualDefault
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode(AutomationProfile.self, from: data)) ?? .manualDefault
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save automation profile: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/AutomationProfileStore.swift \
  tests/AutomationProfileStoreTest.swift \
  -o build/AutomationProfileStoreTest
./build/AutomationProfileStoreTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/AutomationProfileStore.swift tests/AutomationProfileStoreTest.swift
git commit -m "feat: add automation profile store"
```

---

### Task 2: Inbox Store

**Files:**
- Create: `native/MacSoftwareSteward/InboxStore.swift`
- Test: `tests/InboxStoreTest.swift`

- [ ] **Step 1: Write the failing test**

Create `tests/InboxStoreTest.swift`:

```swift
import Foundation

@main
struct InboxStoreTest {
    static func main() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let firstID = UUID()
        let secondID = UUID()
        let first = InboxItem(
            id: firstID,
            kind: .upgradeDecision,
            severity: .warning,
            title: "Node 需要确认",
            summary: "检测到 major 版本升级。",
            sourceID: "brew:formula:node",
            createdAt: Date(timeIntervalSince1970: 10),
            status: .pending,
            actions: [
                InboxAction(title: "查看升级", systemImage: "arrow.down.circle", kind: .openUpdates)
            ]
        )
        let second = InboxItem(
            id: secondID,
            kind: .failureRecovery,
            severity: .critical,
            title: "升级失败",
            summary: "Homebrew 返回非零退出码。",
            sourceID: "job:failed",
            createdAt: Date(timeIntervalSince1970: 20),
            status: .pending,
            actions: [
                InboxAction(title: "查看日志", systemImage: "terminal", kind: .openJobs)
            ]
        )

        let store = InboxStore(fileURL: url)
        precondition(store.items.isEmpty)
        store.add(first)
        store.add(second)
        precondition(store.items.map(\.id) == [secondID, firstID])
        precondition(store.pendingItems.count == 2)

        store.updateStatus(id: firstID, status: .resolved)
        precondition(store.items.first(where: { $0.id == firstID })?.status == .resolved)
        precondition(store.pendingItems.map(\.id) == [secondID])

        let reloaded = InboxStore(fileURL: url)
        precondition(reloaded.items.map(\.id) == [secondID, firstID])
        precondition(reloaded.items.first(where: { $0.id == firstID })?.status == .resolved)

        reloaded.clearResolved()
        precondition(reloaded.items.map(\.id) == [secondID])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  tests/InboxStoreTest.swift \
  -o build/InboxStoreTest
```

Expected: FAIL with errors like `cannot find 'InboxStore' in scope`.

- [ ] **Step 3: Add inbox models and store**

Create `native/MacSoftwareSteward/InboxStore.swift`:

```swift
import Combine
import Foundation

enum InboxItemKind: String, Codable, CaseIterable, Identifiable {
    case upgradeDecision
    case appUpdate
    case failureRecovery
    case sourceIssue
    case permissionIssue
    case automationIssue

    var id: String { rawValue }
}

enum InboxSeverity: String, Codable, CaseIterable, Identifiable {
    case info
    case warning
    case critical

    var id: String { rawValue }
}

enum InboxStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case resolved
    case ignored

    var id: String { rawValue }
}

enum InboxActionKind: String, Codable, CaseIterable, Identifiable {
    case openUpdates
    case openApplications
    case openSources
    case openJobs
    case openSettings
    case rescan

    var id: String { rawValue }
}

struct InboxAction: Codable, Hashable {
    var title: String
    var systemImage: String
    var kind: InboxActionKind
}

struct InboxItem: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: InboxItemKind
    var severity: InboxSeverity
    var title: String
    var summary: String
    var sourceID: String?
    var createdAt: Date
    var status: InboxStatus
    var actions: [InboxAction]

    init(
        id: UUID = UUID(),
        kind: InboxItemKind,
        severity: InboxSeverity,
        title: String,
        summary: String,
        sourceID: String? = nil,
        createdAt: Date = Date(),
        status: InboxStatus = .pending,
        actions: [InboxAction] = []
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.title = title
        self.summary = summary
        self.sourceID = sourceID
        self.createdAt = createdAt
        self.status = status
        self.actions = actions
    }
}

final class InboxStore: ObservableObject {
    static let defaultFileURL: URL = {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)

        return baseURL
            .appendingPathComponent("MacSoftwareSteward", isDirectory: true)
            .appendingPathComponent("inbox.json")
    }()

    @Published private(set) var items: [InboxItem]

    private let fileURL: URL

    init(fileURL: URL = InboxStore.defaultFileURL) {
        self.fileURL = fileURL
        items = Self.load(from: fileURL)
    }

    var pendingItems: [InboxItem] {
        items.filter { $0.status == .pending }
    }

    func add(_ item: InboxItem) {
        items.removeAll { $0.id == item.id }
        items.append(item)
        sortNewestFirst()
        save()
    }

    func updateStatus(id: UUID, status: InboxStatus) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
        save()
    }

    func clearResolved() {
        items.removeAll { $0.status == .resolved }
        save()
    }

    func replaceAll(_ newItems: [InboxItem]) {
        items = newItems
        sortNewestFirst()
        save()
    }

    private func sortNewestFirst() {
        items.sort { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    private static func load(from fileURL: URL) -> [InboxItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = (try? decoder.decode([InboxItem].self, from: data)) ?? []
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save inbox items: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/InboxStore.swift \
  tests/InboxStoreTest.swift \
  -o build/InboxStoreTest
./build/InboxStoreTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/InboxStore.swift tests/InboxStoreTest.swift
git commit -m "feat: add local inbox store"
```

---

### Task 3: App Tab Visibility Policy

**Files:**
- Modify: `native/MacSoftwareSteward/Models.swift`
- Test: `tests/AppTabVisibilityTest.swift`

- [ ] **Step 1: Write the failing test**

Create `tests/AppTabVisibilityTest.swift`:

```swift
import Foundation

@main
struct AppTabVisibilityTest {
    static func main() {
        precondition(AppTab.visibleTabs(advancedModeEnabled: false) == [
            .inbox,
            .applications,
            .history,
            .settings
        ])
        precondition(AppTab.visibleTabs(advancedModeEnabled: true) == [
            .inbox,
            .updates,
            .applications,
            .sources,
            .history,
            .jobs,
            .settings
        ])
        precondition(AppTab.inbox.symbol == "tray.and.arrow.down")
        precondition(AppTab.history.symbol == "clock.arrow.circlepath")
        precondition(AppTab.inbox.usesSearch == false)
        precondition(AppTab.updates.usesSearch == true)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  tests/AppTabVisibilityTest.swift \
  -o build/AppTabVisibilityTest
```

Expected: FAIL with errors for missing `inbox`, `history`, or `visibleTabs`.

- [ ] **Step 3: Replace the `AppTab` enum**

In `native/MacSoftwareSteward/Models.swift`, replace the current `AppTab` enum with:

```swift
enum AppTab: String, CaseIterable, Identifiable {
    case inbox = "待处理"
    case updates = "可升级"
    case applications = "本机应用"
    case sources = "管理来源"
    case history = "历史"
    case jobs = "任务日志"
    case settings = "设置"

    var id: String { rawValue }

    static func visibleTabs(advancedModeEnabled: Bool) -> [AppTab] {
        if advancedModeEnabled {
            return [.inbox, .updates, .applications, .sources, .history, .jobs, .settings]
        }
        return [.inbox, .applications, .history, .settings]
    }

    var symbol: String {
        switch self {
        case .inbox: return "tray.and.arrow.down"
        case .updates: return "arrow.triangle.2.circlepath"
        case .applications: return "macwindow"
        case .sources: return "tray.full"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .jobs: return "terminal"
        }
    }

    var usesSearch: Bool {
        switch self {
        case .updates, .applications, .sources:
            return true
        case .inbox, .history, .settings, .jobs:
            return false
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  tests/AppTabVisibilityTest.swift \
  -o build/AppTabVisibilityTest
./build/AppTabVisibilityTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/Models.swift tests/AppTabVisibilityTest.swift
git commit -m "feat: add default and advanced app tabs"
```

---

### Task 4: Wire Stores And Navigation

**Files:**
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `native/MacSoftwareSteward/App.swift`
- Modify: `native/MacSoftwareSteward/ContentView.swift`

- [ ] **Step 1: Set the default selected tab**

In `native/MacSoftwareSteward/StewardModel.swift`, replace:

```swift
@Published var selectedTab: AppTab = .updates
```

with:

```swift
@Published var selectedTab: AppTab = .inbox
```

- [ ] **Step 2: Add app-level stores**

In `native/MacSoftwareSteward/App.swift`, add state objects near the existing `@StateObject` declarations:

```swift
@StateObject private var automationProfile = AutomationProfileStore()
@StateObject private var inboxStore = InboxStore()
```

Then add the two environment objects to `ContentView()`:

```swift
ContentView()
    .environmentObject(model)
    .environmentObject(updater)
    .environmentObject(launchAtLogin)
    .environmentObject(automationProfile)
    .environmentObject(inboxStore)
    .preferredColorScheme(AppAppearanceResolver.colorScheme(for: currentAppearanceMode))
```

- [ ] **Step 3: Make ContentView read the automation profile**

In `native/MacSoftwareSteward/ContentView.swift`, add this environment object at the top of `ContentView`:

```swift
@EnvironmentObject private var automationProfile: AutomationProfileStore
```

Replace the sidebar list:

```swift
List(AppTab.allCases, selection: $model.selectedTab) { tab in
    Label(tab.rawValue, systemImage: tab.symbol)
        .tag(tab)
}
```

with:

```swift
List(AppTab.visibleTabs(advancedModeEnabled: automationProfile.profile.advancedModeEnabled), selection: $model.selectedTab) { tab in
    Label(tab.rawValue, systemImage: tab.symbol)
        .tag(tab)
}
```

Add this modifier to the outer `NavigationSplitView`, after the existing `.sheet` modifiers:

```swift
.onChange(of: automationProfile.profile.advancedModeEnabled) {
    let visibleTabs = AppTab.visibleTabs(advancedModeEnabled: automationProfile.profile.advancedModeEnabled)
    if !visibleTabs.contains(model.selectedTab) {
        model.selectedTab = .inbox
    }
}
```

- [ ] **Step 4: Route the new tabs**

In `MainPanel`, add environment objects:

```swift
@EnvironmentObject private var automationProfile: AutomationProfileStore
@EnvironmentObject private var inboxStore: InboxStore
```

In the `switch model.selectedTab` group, replace the current switch with:

```swift
switch model.selectedTab {
case .inbox:
    InboxView()
case .updates:
    UpdatesView()
case .applications:
    ApplicationsView()
case .sources:
    SourcesView()
case .history:
    HistoryView()
case .settings:
    SettingsView()
case .jobs:
    JobsView()
}
```

- [ ] **Step 5: Build to catch wiring errors**

Run:

```bash
npm run build
```

Expected: FAIL because `InboxView` and `HistoryView` do not exist yet. The failure should mention missing `InboxView` or `HistoryView`.

- [ ] **Step 6: Commit after Task 5 creates the missing views**

No commit in this task yet. Commit the wiring together with the new views in Task 5 so the app build never lands in a broken state.

---

### Task 5: Inbox And History Views

**Files:**
- Create: `native/MacSoftwareSteward/Views/InboxView.swift`
- Create: `native/MacSoftwareSteward/Views/HistoryView.swift`

- [ ] **Step 1: Create InboxView**

Create `native/MacSoftwareSteward/Views/InboxView.swift`:

```swift
import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore

    private var pendingItems: [InboxItem] {
        inboxStore.pendingItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !automationProfile.profile.onboardingCompleted {
                AutomationOnboardingCard()
                    .environmentObject(automationProfile)
            }

            AutomationSummaryCard()
                .environmentObject(model)
                .environmentObject(automationProfile)
                .environmentObject(inboxStore)

            if pendingItems.isEmpty {
                EmptyStateView(
                    symbol: "checkmark.circle",
                    title: "暂无待处理事项",
                    text: "需要确认的升级、失败恢复和来源异常会出现在这里。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(pendingItems) { item in
                            InboxItemRow(item: item)
                                .environmentObject(model)
                                .environmentObject(automationProfile)
                                .environmentObject(inboxStore)
                        }
                    }
                }
            }
        }
    }
}

private struct AutomationOnboardingCard: View {
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "wand.and.stars")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("开启自动化管家")
                    .font(.system(.headline, design: .rounded))
                Text("默认只自动处理低风险升级；需要确认或失败时再提醒。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("保持手动") {
                automationProfile.completeOnboarding(enableAutomation: false)
            }
            .buttonStyle(.bordered)

            Button("开启") {
                automationProfile.completeOnboarding(enableAutomation: true)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct AutomationSummaryCard: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore

    var body: some View {
        HStack(spacing: 10) {
            SummaryPill(
                title: "自动化",
                value: automationProfile.profile.automationEnabled ? "已开启" : "手动模式",
                symbol: automationProfile.profile.automationEnabled ? "checkmark.shield" : "hand.raised"
            )
            SummaryPill(
                title: "待处理",
                value: "\(inboxStore.pendingItems.count)",
                symbol: "tray.and.arrow.down"
            )
            SummaryPill(
                title: "可操作升级",
                value: "\(model.availableUpdates.count)",
                symbol: "arrow.down.circle"
            )
            SummaryPill(
                title: "高级模式",
                value: automationProfile.profile.advancedModeEnabled ? "已开启" : "已关闭",
                symbol: "slider.horizontal.3"
            )
        }
    }
}

private struct SummaryPill: View {
    var title: String
    var value: String
    var symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.headline, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct InboxItemRow: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore
    var item: InboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: severitySymbol(item.severity))
                    .font(.title3)
                    .foregroundStyle(severityColor(item.severity))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(.headline, design: .rounded))
                    Text(item.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Badge(text: severityTitle(item.severity), color: severityColor(item.severity))
            }

            HStack(spacing: 8) {
                ForEach(item.actions, id: \.self) { action in
                    Button {
                        perform(action.kind)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                Button {
                    inboxStore.updateStatus(id: item.id, status: .resolved)
                } label: {
                    Label("完成", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderless)

                Button {
                    inboxStore.updateStatus(id: item.id, status: .ignored)
                } label: {
                    Label("忽略", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(severityColor(item.severity).opacity(0.18), lineWidth: 1)
        )
    }

    private func perform(_ kind: InboxActionKind) {
        switch kind {
        case .openUpdates:
            open(tab: .updates)
        case .openApplications:
            open(tab: .applications)
        case .openSources:
            open(tab: .sources)
        case .openJobs:
            open(tab: .jobs)
        case .openSettings:
            open(tab: .settings)
        case .rescan:
            Task { await model.scanSoftware() }
        }
    }

    private func open(tab: AppTab) {
        let visibleTabs = AppTab.visibleTabs(advancedModeEnabled: automationProfile.profile.advancedModeEnabled)
        if !visibleTabs.contains(tab) {
            automationProfile.setAdvancedMode(true)
        }
        model.selectedTab = tab
    }
}

private func severityTitle(_ severity: InboxSeverity) -> String {
    switch severity {
    case .info: return "信息"
    case .warning: return "需确认"
    case .critical: return "严重"
    }
}

private func severitySymbol(_ severity: InboxSeverity) -> String {
    switch severity {
    case .info: return "info.circle"
    case .warning: return "exclamationmark.triangle"
    case .critical: return "xmark.octagon"
    }
}

private func severityColor(_ severity: InboxSeverity) -> Color {
    switch severity {
    case .info: return .blue
    case .warning: return .orange
    case .critical: return .red
    }
}
```

- [ ] **Step 2: Create HistoryView**

Create `native/MacSoftwareSteward/Views/HistoryView.swift`:

```swift
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        if model.historyStore.records.isEmpty {
            EmptyStateView(
                symbol: "clock.arrow.circlepath",
                title: "暂无历史记录",
                text: "升级完成、失败恢复和后续巡检记录会保存在这里。"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.historyStore.records) { record in
                        HistoryRecordRow(record: record)
                    }
                }
            }
        }
    }
}

private struct HistoryRecordRow: View {
    var record: UpgradeHistoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: record.status == "完成" ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(record.status == "完成" ? .green : .orange)

                Text(record.label)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)

                Spacer()

                Badge(text: record.status, color: record.status == "完成" ? .green : .orange)
            }

            Text(record.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let startedAt = record.startedAt {
                    Text(startedAt, style: .date)
                    Text(startedAt, style: .time)
                }
                if let exitCode = record.exitCode {
                    Text("退出码 \(exitCode)")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
```

- [ ] **Step 3: Build to verify navigation and views**

Run:

```bash
npm run build
```

Expected: build succeeds and produces `build/MacSoftwareSteward.app`.

- [ ] **Step 4: Commit Tasks 4 and 5 together**

```bash
git add \
  native/MacSoftwareSteward/StewardModel.swift \
  native/MacSoftwareSteward/App.swift \
  native/MacSoftwareSteward/ContentView.swift \
  native/MacSoftwareSteward/Views/InboxView.swift \
  native/MacSoftwareSteward/Views/HistoryView.swift
git commit -m "feat: add inbox landing experience"
```

---

### Task 6: Automation Settings Controls

**Files:**
- Modify: `native/MacSoftwareSteward/Views/SettingsView.swift`

- [ ] **Step 1: Add automation store environment**

At the top of `SettingsView`, add:

```swift
@EnvironmentObject private var automationProfile: AutomationProfileStore
```

- [ ] **Step 2: Add automation settings group**

In the `VStack` inside `SettingsView.body`, insert this group after the existing "通用" group:

```swift
SettingsGroupBox {
    SettingsGroupHeader(title: "自动化管家", symbol: "wand.and.stars")
    AutomationProfileRow()
    SettingsDivider()
    AdvancedModeRow()
    SettingsDivider()
    NotificationPolicyRow()
    if automationProfile.profile.advancedModeEnabled {
        SettingsDivider()
        RegularAppNetworkPolicyRow()
        SettingsDivider()
        AutoRepairPolicyRow()
    }
}
```

- [ ] **Step 3: Add row views at the end of the file**

Append these views to `native/MacSoftwareSteward/Views/SettingsView.swift`:

```swift
struct AutomationProfileRow: View {
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("自动化管家")
                    .font(.body)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if automationProfile.profile.onboardingCompleted {
                Toggle("", isOn: Binding(
                    get: { automationProfile.profile.automationEnabled },
                    set: { automationProfile.setAutomationEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            } else {
                Button("开启") {
                    automationProfile.completeOnboarding(enableAutomation: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("保持手动") {
                    automationProfile.completeOnboarding(enableAutomation: false)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var statusText: String {
        if !automationProfile.profile.onboardingCompleted {
            return "首次开启后只自动处理低风险维护事项"
        }
        return automationProfile.profile.automationEnabled ? "低风险维护可自动处理" : "当前保持手动维护"
    }
}

struct AdvancedModeRow: View {
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("高级模式")
                    .font(.body)
                Text("显示可升级、管理来源、任务日志和高级策略")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { automationProfile.profile.advancedModeEnabled },
                set: { automationProfile.setAdvancedMode($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }
}

struct NotificationPolicyRow: View {
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack {
            Text("通知")
                .font(.body)
            Spacer()
            Picker("", selection: Binding(
                get: { automationProfile.profile.notificationPolicy },
                set: { automationProfile.setNotificationPolicy($0) }
            )) {
                ForEach(NotificationPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .frame(width: 220)
            .labelsHidden()
        }
    }
}

struct RegularAppNetworkPolicyRow: View {
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("普通 App 联网检查")
                    .font(.body)
                Text("控制 Sparkle 和厂商更新源检查范围")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { automationProfile.profile.regularAppNetworkPolicy },
                set: { automationProfile.setRegularAppNetworkPolicy($0) }
            )) {
                ForEach(RegularAppNetworkPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .frame(width: 220)
            .labelsHidden()
        }
    }
}

struct AutoRepairPolicyRow: View {
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("失败恢复")
                    .font(.body)
                Text("控制是否允许低风险恢复动作自动执行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { automationProfile.profile.autoRepairPolicy },
                set: { automationProfile.setAutoRepairPolicy($0) }
            )) {
                ForEach(AutoRepairPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .frame(width: 220)
            .labelsHidden()
        }
    }
}
```

- [ ] **Step 4: Build to verify settings compile**

Run:

```bash
npm run build
```

Expected: build succeeds and produces `build/MacSoftwareSteward.app`.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/Views/SettingsView.swift
git commit -m "feat: add automation settings controls"
```

---

### Task 7: Wire Tests Into Native Test Script

**Files:**
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Add test entries**

In `scripts/test-native.sh`, add these entries after `run_test AppWindowDoubleClickZoomPolicyTest ...` and before `run_test BrewCaskCleanupDetectorTest ...`:

```bash
run_test AppTabVisibilityTest \
  "$SRC/Models.swift" \
  "$TESTS/AppTabVisibilityTest.swift"

run_test AutomationProfileStoreTest \
  "$SRC/AutomationProfileStore.swift" \
  "$TESTS/AutomationProfileStoreTest.swift"
```

Add this entry after `run_test HomebrewDownloadMonitorTest ...` and before `run_test PackageProgressParserTest ...`:

```bash
run_test InboxStoreTest \
  "$SRC/InboxStore.swift" \
  "$TESTS/InboxStoreTest.swift"
```

- [ ] **Step 2: Run the full native test suite**

Run:

```bash
npm test
```

Expected: all native tests build and run, ending with `All native tests passed.`

- [ ] **Step 3: Run the app build**

Run:

```bash
npm run build
```

Expected: build succeeds and produces `build/MacSoftwareSteward.app`.

- [ ] **Step 4: Commit**

```bash
git add scripts/test-native.sh
git commit -m "test: cover automation profile and inbox stores"
```

---

### Task 8: Manual Smoke Check

**Files:**
- No source changes expected.

- [ ] **Step 1: Build and open the app**

Run:

```bash
npm run open
```

Expected: the app opens with the sidebar defaulting to `待处理`.

- [ ] **Step 2: Check default mode navigation**

In the app sidebar, confirm the visible tabs are exactly:

```text
待处理
本机应用
历史
设置
```

- [ ] **Step 3: Check automation onboarding**

In `待处理`, click `保持手动`.

Expected: the onboarding card disappears, the summary shows `手动模式`, and the empty state remains visible if no inbox items exist.

- [ ] **Step 4: Check advanced mode**

Open `设置`, turn on `高级模式`.

Expected: the sidebar now includes:

```text
待处理
可升级
本机应用
管理来源
历史
任务日志
设置
```

- [ ] **Step 5: Check advanced mode fallback**

Select `任务日志`, then return to `设置` and turn off `高级模式`.

Expected: the selected tab falls back to `待处理`, and advanced-only tabs disappear.

- [ ] **Step 6: Final status check**

Run:

```bash
git status --short
```

Expected: only intentional changes remain. The existing untracked `code-risk-scanner/` directory may still appear and should not be staged by this plan.

