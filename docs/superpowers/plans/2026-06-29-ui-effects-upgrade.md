# UI and Effects Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade Mac Software Steward into a polished native macOS maintenance console with state-driven visual effects and consistent task surfaces.

**Architecture:** Add one small presenter for testable maintenance-status copy and semantic roles, then use existing SwiftUI views for the visual upgrade. Keep all scan, upgrade, policy, persistence, and automation behavior unchanged; UI reads existing `StewardModel` and `AutomationProfileStore` state.

**Tech Stack:** SwiftUI + AppKit, macOS 14.0+, direct `xcrun swiftc` builds through `scripts/build-native.sh` and `scripts/test-native.sh`.

## Global Constraints

- Keep UI copy in Chinese and code identifiers in English.
- Do not add external UI dependencies.
- Do not replace SwiftUI/AppKit with a web UI.
- Do not redesign scanner, upgrade planner, policy, inbox, history, source, or persistence logic.
- Do not reintroduce hidden navigation pages or change advanced-mode semantics.
- Do not create a marketing-style landing page, oversized hero, decorative orbs, or a one-note purple/blue gradient theme.
- Do not edit generated app icons or release artifacts.
- Respect macOS native conventions, system appearance, accent color, keyboard focus, and reduced-motion settings.
- Guard macOS 15-only symbol effects with availability checks.

---

## File Structure

- Create `native/MacSoftwareSteward/MaintenanceStatusPresenter.swift`
  - Pure presenter for status-band/sidebar status copy, SF Symbols, semantic tint roles, activity flag, and optional progress.
- Create `tests/MaintenanceStatusPresenterTest.swift`
  - Single-file Swift test covering idle, pending updates, scanning, running upgrade, and failed package states.
- Modify `scripts/test-native.sh`
  - Register `MaintenanceStatusPresenterTest` with the existing hand-written test runner.
- Modify `native/MacSoftwareSteward/Views/SharedComponents.swift`
  - Add small SwiftUI visual primitives for polished surfaces, animated accent lines, refined progress bars, and shared task-card styling.
  - Upgrade existing shared components that already represent global UI language: `WarningLine`, `InstallToolPrompt`, `EmptyStateView`, and `UpgradeProgressBar`.
- Modify `native/MacSoftwareSteward/ContentView.swift`
  - Use `MaintenanceStatusPresenter` in the sidebar chip and main header.
  - Add the live maintenance status band under the toolbar row.
  - Refine sidebar selected/hover visuals and detail transitions.
- Modify `native/MacSoftwareSteward/Views/UpdatesView.swift`
  - Upgrade scanning state, filter/header controls, update row card treatment, active row feedback, failure row treatment, and per-package progress details.

---

### Task 1: Maintenance Status Presenter

**Files:**
- Create: `native/MacSoftwareSteward/MaintenanceStatusPresenter.swift`
- Create: `tests/MaintenanceStatusPresenterTest.swift`
- Modify: `scripts/test-native.sh`

**Interfaces:**
- Consumes: `UpgradeProgress`
- Produces:
  - `enum MaintenanceStatusTintRole: String, Equatable`
  - `struct MaintenanceStatusPresentation: Equatable`
  - `enum MaintenanceStatusPresenter`
  - `static func presentation(isScanning: Bool, scanPhaseText: String?, scanProgress: Double?, hasRunningJob: Bool, upgradeProgress: UpgradeProgress?, updateCount: Int, failedPackageCount: Int) -> MaintenanceStatusPresentation`

- [ ] **Step 1: Write the failing test**

Create `tests/MaintenanceStatusPresenterTest.swift`:

```swift
import Foundation

@main
struct MaintenanceStatusPresenterTest {
    static func main() {
        let idle = MaintenanceStatusPresenter.presentation(
            isScanning: false,
            scanPhaseText: nil,
            scanProgress: nil,
            hasRunningJob: false,
            upgradeProgress: nil,
            updateCount: 0,
            failedPackageCount: 0
        )
        precondition(idle.title == "维护状态良好", "Unexpected idle title: \(idle.title)")
        precondition(idle.detail == "没有发现可操作升级", "Unexpected idle detail: \(idle.detail)")
        precondition(idle.symbol == "checkmark.seal", "Unexpected idle symbol: \(idle.symbol)")
        precondition(idle.tintRole == .success)
        precondition(!idle.isActive)
        precondition(idle.progress == nil)

        let pending = MaintenanceStatusPresenter.presentation(
            isScanning: false,
            scanPhaseText: nil,
            scanProgress: nil,
            hasRunningJob: false,
            upgradeProgress: nil,
            updateCount: 3,
            failedPackageCount: 0
        )
        precondition(pending.title == "发现 3 个可升级项目", "Unexpected pending title: \(pending.title)")
        precondition(pending.detail == "可先检查策略，再执行一键升级", "Unexpected pending detail: \(pending.detail)")
        precondition(pending.symbol == "arrow.down.circle", "Unexpected pending symbol: \(pending.symbol)")
        precondition(pending.tintRole == .attention)
        precondition(!pending.isActive)

        let scanning = MaintenanceStatusPresenter.presentation(
            isScanning: true,
            scanPhaseText: "正在获取 Homebrew 信息...",
            scanProgress: 0.25,
            hasRunningJob: false,
            upgradeProgress: nil,
            updateCount: 0,
            failedPackageCount: 0
        )
        precondition(scanning.title == "正在扫描本机软件", "Unexpected scanning title: \(scanning.title)")
        precondition(scanning.detail == "正在获取 Homebrew 信息...", "Unexpected scanning detail: \(scanning.detail)")
        precondition(scanning.symbol == "magnifyingglass", "Unexpected scanning symbol: \(scanning.symbol)")
        precondition(scanning.tintRole == .scanning)
        precondition(scanning.isActive)
        precondition(scanning.progress == 0.25)

        let progress = UpgradeProgress(completed: 1, total: 4, failed: 0, currentPackage: "iina")
        let upgrading = MaintenanceStatusPresenter.presentation(
            isScanning: false,
            scanPhaseText: nil,
            scanProgress: nil,
            hasRunningJob: true,
            upgradeProgress: progress,
            updateCount: 4,
            failedPackageCount: 0
        )
        precondition(upgrading.title == "正在执行升级", "Unexpected upgrading title: \(upgrading.title)")
        precondition(upgrading.detail == "已完成 1/4 · 当前 iina", "Unexpected upgrading detail: \(upgrading.detail)")
        precondition(upgrading.symbol == "bolt.circle", "Unexpected upgrading symbol: \(upgrading.symbol)")
        precondition(upgrading.tintRole == .accent)
        precondition(upgrading.isActive)
        precondition(upgrading.progress == 0.25)

        let failed = MaintenanceStatusPresenter.presentation(
            isScanning: false,
            scanPhaseText: nil,
            scanProgress: nil,
            hasRunningJob: false,
            upgradeProgress: nil,
            updateCount: 2,
            failedPackageCount: 2
        )
        precondition(failed.title == "有 2 个升级需要处理", "Unexpected failed title: \(failed.title)")
        precondition(failed.detail == "失败项保留在列表中，可重试或查看日志", "Unexpected failed detail: \(failed.detail)")
        precondition(failed.symbol == "exclamationmark.triangle", "Unexpected failed symbol: \(failed.symbol)")
        precondition(failed.tintRole == .failure)
        precondition(!failed.isActive)
    }
}
```

- [ ] **Step 2: Register and run the failing test**

Modify `scripts/test-native.sh` after `AppTabVisibilityTest`:

```bash
run_test MaintenanceStatusPresenterTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/MaintenanceStatusPresenter.swift" \
  "$TESTS/MaintenanceStatusPresenterTest.swift"
```

Run:

```bash
bash scripts/test-native.sh
```

Expected: FAIL while building `MaintenanceStatusPresenterTest` because `native/MacSoftwareSteward/MaintenanceStatusPresenter.swift` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `native/MacSoftwareSteward/MaintenanceStatusPresenter.swift`:

```swift
import Foundation

enum MaintenanceStatusTintRole: String, Equatable {
    case neutral
    case accent
    case scanning
    case attention
    case success
    case failure
}

struct MaintenanceStatusPresentation: Equatable {
    var title: String
    var detail: String
    var symbol: String
    var tintRole: MaintenanceStatusTintRole
    var isActive: Bool
    var progress: Double?
}

enum MaintenanceStatusPresenter {
    static func presentation(
        isScanning: Bool,
        scanPhaseText: String?,
        scanProgress: Double?,
        hasRunningJob: Bool,
        upgradeProgress: UpgradeProgress?,
        updateCount: Int,
        failedPackageCount: Int
    ) -> MaintenanceStatusPresentation {
        if isScanning {
            return MaintenanceStatusPresentation(
                title: "正在扫描本机软件",
                detail: scanPhaseText ?? "准备刷新软件状态",
                symbol: "magnifyingglass",
                tintRole: .scanning,
                isActive: true,
                progress: scanProgress
            )
        }

        if hasRunningJob {
            let detail: String
            if let upgradeProgress {
                if let currentPackage = upgradeProgress.currentPackage, !currentPackage.isEmpty {
                    detail = "已完成 \(upgradeProgress.completed)/\(upgradeProgress.total) · 当前 \(currentPackage)"
                } else {
                    detail = "已完成 \(upgradeProgress.completed)/\(upgradeProgress.total)"
                }
            } else {
                detail = "升级任务正在执行"
            }
            return MaintenanceStatusPresentation(
                title: "正在执行升级",
                detail: detail,
                symbol: "bolt.circle",
                tintRole: .accent,
                isActive: true,
                progress: upgradeProgress?.fraction
            )
        }

        if failedPackageCount > 0 {
            return MaintenanceStatusPresentation(
                title: "有 \(failedPackageCount) 个升级需要处理",
                detail: "失败项保留在列表中，可重试或查看日志",
                symbol: "exclamationmark.triangle",
                tintRole: .failure,
                isActive: false,
                progress: nil
            )
        }

        if updateCount > 0 {
            return MaintenanceStatusPresentation(
                title: "发现 \(updateCount) 个可升级项目",
                detail: "可先检查策略，再执行一键升级",
                symbol: "arrow.down.circle",
                tintRole: .attention,
                isActive: false,
                progress: nil
            )
        }

        return MaintenanceStatusPresentation(
            title: "维护状态良好",
            detail: "没有发现可操作升级",
            symbol: "checkmark.seal",
            tintRole: .success,
            isActive: false,
            progress: nil
        )
    }
}
```

- [ ] **Step 4: Run the presenter test**

Run:

```bash
bash scripts/test-native.sh
```

Expected: PASS through `MaintenanceStatusPresenterTest` and continue through the rest of the native tests.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/MaintenanceStatusPresenter.swift tests/MaintenanceStatusPresenterTest.swift scripts/test-native.sh
git commit -m "feat: add maintenance status presenter"
```

---

### Task 2: Shared Visual Primitives

**Files:**
- Modify: `native/MacSoftwareSteward/Views/SharedComponents.swift`

**Interfaces:**
- Consumes: `MaintenanceStatusTintRole`, `MaintenanceStatusPresentation`, `UpgradeProgress`, `PackageUpgradeProgress`
- Produces:
  - `func tintColor(for role: MaintenanceStatusTintRole) -> Color`
  - `extension View.stewardSymbolPulse(active:)`
  - `struct FlowingAccentLine: View`
  - `struct PolishedTaskSurfaceModifier: ViewModifier`
  - `extension View.polishedTaskSurface(tint:isActive:)`
  - `struct StatusIconPlate: View`
  - Refined `EmptyStateView`, `WarningLine`, `InstallToolPrompt`, and `UpgradeProgressBar`

- [ ] **Step 1: Add semantic tint mapping**

Add near the shared utility functions in `SharedComponents.swift`:

```swift
func tintColor(for role: MaintenanceStatusTintRole) -> Color {
    switch role {
    case .neutral:
        return .secondary
    case .accent:
        return .accentColor
    case .scanning:
        return .cyan
    case .attention:
        return .orange
    case .success:
        return .green
    case .failure:
        return .red
    }
}
```

- [ ] **Step 2: Add shared symbol guard, animated accent, and surface primitives**

Add these SwiftUI views above `Badge`:

```swift
extension View {
    @ViewBuilder
    func stewardSymbolPulse(active: Bool) -> some View {
        if #available(macOS 15.0, *) {
            self.symbolEffect(.pulse, options: .repeating, isActive: active)
        } else {
            self
        }
    }
}

struct FlowingAccentLine: View {
    var tint: Color
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(isActive ? 0.18 : 0.12))

                if isActive && !reduceMotion {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, tint.opacity(0.85), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(80, proxy.size.width * 0.32))
                        .offset(x: offset * proxy.size.width)
                }
            }
        }
        .frame(height: 2)
        .clipShape(Capsule())
        .onAppear {
            guard isActive && !reduceMotion else { return }
            offset = -0.35
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                offset = 1.05
            }
        }
        .onChange(of: isActive) {
            guard isActive && !reduceMotion else {
                offset = -0.35
                return
            }
            offset = -0.35
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                offset = 1.05
            }
        }
    }
}

struct PolishedTaskSurfaceModifier: ViewModifier {
    var tint: Color
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .background(
                LinearGradient(
                    colors: [
                        tint.opacity(isActive ? 0.08 : 0.035),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tint.opacity(isActive ? 0.24 : 0.10), lineWidth: 1)
            )
            .shadow(color: tint.opacity(isActive && !reduceMotion ? 0.10 : 0.03), radius: isActive ? 10 : 4, y: 2)
    }
}

extension View {
    func polishedTaskSurface(tint: Color = .accentColor, isActive: Bool = false) -> some View {
        modifier(PolishedTaskSurfaceModifier(tint: tint, isActive: isActive))
    }
}

struct StatusIconPlate: View {
    var symbol: String
    var tint: Color
    var isActive = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(isActive ? 0.20 : 0.14), tint.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 34, height: 34)

            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .stewardSymbolPulse(active: isActive)
        }
    }
}
```

- [ ] **Step 3: Refine shared empty, warning, install, and progress components**

Update `WarningLine`, `InstallToolPrompt`, and `EmptyStateView` to use `polishedTaskSurface`. Keep their existing public initializers unchanged. Replace the body backgrounds with:

```swift
.polishedTaskSurface(tint: .red, isActive: false)
```

for `WarningLine`, and:

```swift
.polishedTaskSurface(tint: .accentColor, isActive: false)
```

for `InstallToolPrompt`.

For `EmptyStateView`, keep the same arguments and replace the circle block with:

```swift
StatusIconPlate(symbol: symbol, tint: .secondary)
```

Then update `UpgradeProgressBar` so the outer container ends with:

```swift
.padding(.horizontal, 14)
.padding(.vertical, 12)
.polishedTaskSurface(tint: progress.failed > 0 && !progress.isRunning ? .orange : .accentColor, isActive: progress.isRunning)
```

and add a `FlowingAccentLine` directly below the `ProgressView`:

```swift
FlowingAccentLine(
    tint: progress.failed > 0 && !progress.isRunning ? .orange : .accentColor,
    isActive: progress.isRunning
)
```

- [ ] **Step 4: Build after shared visual primitives**

Run:

```bash
npm run build
```

Expected: build succeeds and `build/MacSoftwareSteward.app` is created.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/Views/SharedComponents.swift
git commit -m "feat: add shared ui effects"
```

---

### Task 3: Header Status Band and Sidebar Polish

**Files:**
- Modify: `native/MacSoftwareSteward/ContentView.swift`

**Interfaces:**
- Consumes:
  - `MaintenanceStatusPresenter.presentation(...)`
  - `MaintenanceStatusPresentation`
  - `tintColor(for:)`
  - `FlowingAccentLine`
  - `StatusIconPlate`
  - `polishedTaskSurface(tint:isActive:)`
  - `stewardSymbolPulse(active:)`
- Produces:
  - `private var failedPackageCount: Int` inside `HeaderView`
  - `private var statusPresentation: MaintenanceStatusPresentation` inside `HeaderView`
  - `private struct MaintenanceStatusBand: View`
  - Sidebar chip that uses the same presenter state as the main header

- [ ] **Step 1: Replace sidebar status calculation with presenter-backed state**

In `SidebarStatusChip`, replace the current tuple `status` with:

```swift
private var presentation: MaintenanceStatusPresentation {
    MaintenanceStatusPresenter.presentation(
        isScanning: model.isScanning,
        scanPhaseText: model.scanPhase?.rawValue,
        scanProgress: model.scanPhase?.progress,
        hasRunningJob: model.hasRunningJob,
        upgradeProgress: model.upgradeProgress,
        updateCount: model.allUpgradeablePackages.count,
        failedPackageCount: model.packageProgress.values.filter { progress in
            [.failed, .timedOut, .cancelled].contains(progress.status)
        }.count
    )
}

private var tint: Color {
    tintColor(for: presentation.tintRole)
}
```

Update `SidebarStatusChip.body` to use:

```swift
Image(systemName: presentation.symbol)
    .font(.system(size: 12, weight: .semibold))
    .foregroundStyle(tint)
    .frame(width: 18)
    .stewardSymbolPulse(active: presentation.isActive)

Text(presentation.title)
Text(presentation.detail)
```

and replace its background/overlay with:

```swift
.polishedTaskSurface(tint: tint, isActive: presentation.isActive)
```

Remove the private `symbolEffectIfAvailable(active:)` extension from `ContentView.swift` after all calls in that file have moved to `stewardSymbolPulse(active:)`.

- [ ] **Step 2: Refine sidebar row selected and hover treatment**

In `SidebarRow.body`, after the existing `.background(rowBackground, in: RoundedRectangle(cornerRadius: 8))`, add:

```swift
.overlay(
    RoundedRectangle(cornerRadius: 8)
        .stroke(rowBorderColor, lineWidth: rowState == .selected ? 1 : 0.5)
)
```

Add:

```swift
private var rowBorderColor: Color {
    switch rowState {
    case .normal:
        return Color.clear
    case .hovered:
        return Color.primary.opacity(0.08)
    case .selected:
        return Color.accentColor.opacity(0.22)
    }
}
```

Change `rowBackground` to:

```swift
private var rowBackground: Color {
    switch rowState {
    case .normal:
        return Color.clear
    case .hovered:
        return Color.primary.opacity(0.06)
    case .selected:
        return Color.accentColor.opacity(0.14)
    }
}
```

- [ ] **Step 3: Add status presentation helpers to HeaderView**

Inside `HeaderView`, add:

```swift
private var failedPackageCount: Int {
    model.packageProgress.values.filter { progress in
        [.failed, .timedOut, .cancelled].contains(progress.status)
    }.count
}

private var statusPresentation: MaintenanceStatusPresentation {
    MaintenanceStatusPresenter.presentation(
        isScanning: model.isScanning,
        scanPhaseText: model.scanPhase?.rawValue,
        scanProgress: model.scanPhase?.progress,
        hasRunningJob: model.hasRunningJob,
        upgradeProgress: model.upgradeProgress,
        updateCount: model.allUpgradeablePackages.count,
        failedPackageCount: failedPackageCount
    )
}
```

- [ ] **Step 4: Insert the maintenance status band**

In `HeaderView.body`, place `MaintenanceStatusBand(presentation: statusPresentation, updateCount: model.allUpgradeablePackages.count, failedCount: failedPackageCount)` between `toolbarRow` and the conditional banners:

```swift
toolbarRow

MaintenanceStatusBand(
    presentation: statusPresentation,
    updateCount: model.allUpgradeablePackages.count,
    failedCount: failedPackageCount
)
```

Add this new view below `HeaderView`:

```swift
private struct MaintenanceStatusBand: View {
    var presentation: MaintenanceStatusPresentation
    var updateCount: Int
    var failedCount: Int

    private var tint: Color {
        tintColor(for: presentation.tintRole)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                StatusIconPlate(symbol: presentation.symbol, tint: tint, isActive: presentation.isActive)

                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(presentation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                statusMetric(title: "可升级", value: updateCount, tint: .orange)
                statusMetric(title: "需处理", value: failedCount, tint: failedCount > 0 ? .red : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if let progress = presentation.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            FlowingAccentLine(tint: tint, isActive: presentation.isActive)
        }
        .polishedTaskSurface(tint: tint, isActive: presentation.isActive)
        .animation(.easeOut(duration: 0.18), value: presentation)
    }

    private func statusMetric(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 52, alignment: .trailing)
    }
}
```

- [ ] **Step 5: Build after header/sidebar changes**

Run:

```bash
npm run build
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/ContentView.swift
git commit -m "feat: add maintenance status band"
```

---

### Task 4: Updates View Task Cards and State Effects

**Files:**
- Modify: `native/MacSoftwareSteward/Views/UpdatesView.swift`

**Interfaces:**
- Consumes:
  - `StatusIconPlate`
  - `FlowingAccentLine`
  - `polishedTaskSurface(tint:isActive:)`
  - existing `PackageStatusBadge`, `PackageProgressBadge`, `PackageProgressDetail`
- Produces:
  - More polished scanning state
  - Refined update filter/header row
  - Active/failure-aware update row surface

- [ ] **Step 1: Refine the filter/header row**

Replace the top `HStack` in `UpdatesView.body` with:

```swift
HStack(alignment: .center, spacing: 12) {
    VStack(alignment: .leading, spacing: 4) {
        Text("可执行升级")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
        Text("Homebrew 与 Mac App Store 中可直接执行的升级会出现在这里。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    Spacer(minLength: 12)

    Picker("", selection: $selectedFilter) {
        ForEach(UpdateFilter.allCases) { filter in
            Text(filter.rawValue).tag(filter)
        }
    }
    .labelsHidden()
    .pickerStyle(.segmented)
    .frame(width: 420)

    Button {
        model.selectedTab = .rules
    } label: {
        Label("升级策略", systemImage: "slider.horizontal.3")
            .font(.caption)
    }
    .buttonStyle(.borderless)
}
.padding(12)
.polishedTaskSurface(tint: .accentColor, isActive: false)
```

- [ ] **Step 2: Upgrade scanning state**

Replace `scanningView` with:

```swift
private var scanningView: some View {
    VStack(spacing: 18) {
        StatusIconPlate(symbol: "arrow.triangle.2.circlepath", tint: .cyan, isActive: true)
            .scaleEffect(1.2)

        VStack(spacing: 8) {
            Text("正在扫描本机软件")
                .font(.system(.headline, design: .rounded))
            if let phase = model.scanPhase {
                Text(phase.rawValue)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                ProgressView(value: phase.progress)
                    .progressViewStyle(.linear)
                    .tint(.cyan)
                    .frame(maxWidth: 320)
                FlowingAccentLine(tint: .cyan, isActive: true)
                    .frame(maxWidth: 320)
            } else {
                Text("准备刷新软件状态")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }
    .frame(maxWidth: .infinity, minHeight: 300)
    .polishedTaskSurface(tint: .cyan, isActive: true)
}
```

Keep the existing `scanningIcon` helper until the file compiles, then remove it if it is unused.

- [ ] **Step 3: Upgrade UpdateRow surface**

In `UpdateRow.body`, replace the source icon `ZStack` with:

```swift
StatusIconPlate(
    symbol: package.source.contains("Brew") ? "shippingbox" : "bag",
    tint: sourceIconColor,
    isActive: progress?.status == .running
)
```

Replace the final row background/overlay block:

```swift
.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
.background(rowTint, in: RoundedRectangle(cornerRadius: 12))
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(rowBorder, lineWidth: 1)
)
```

with:

```swift
.polishedTaskSurface(tint: rowAccent, isActive: isActiveRow)
```

Add:

```swift
private var isActiveRow: Bool {
    progress?.status == .running || progress?.status == .queued
}

private var rowAccent: Color {
    switch progress?.status {
    case .running, .queued:
        return .accentColor
    case .succeeded:
        return .green
    case .failed, .cancelled, .timedOut:
        return .red
    case .warning:
        return .yellow
    case nil:
        return package.outdated ? .orange : .secondary
    }
}
```

Keep `rowTint` and `rowBorder` until all references are removed, then delete them.

- [ ] **Step 4: Add active row accent line**

Inside `UpdateRow.body`, after `PackageProgressDetail(progress: progress)`, add:

```swift
if isActiveRow {
    FlowingAccentLine(tint: rowAccent, isActive: true)
        .padding(.leading, 40)
}
```

- [ ] **Step 5: Refine progress detail progress bars**

In `PackageProgressDetail.runningProgress`, after each determinate `ProgressView(value: fraction)` add:

```swift
FlowingAccentLine(tint: .accentColor, isActive: true)
```

For the indeterminate `ProgressView()`, add the same `FlowingAccentLine` below it when `progress.status == .running`.

- [ ] **Step 6: Run tests and build**

Run:

```bash
npm test
npm run build
```

Expected: all native tests pass and the app builds.

- [ ] **Step 7: Commit**

```bash
git add native/MacSoftwareSteward/Views/UpdatesView.swift
git commit -m "feat: polish update task cards"
```

---

### Task 5: Final Consistency Pass and Verification

**Files:**
- Modify: `native/MacSoftwareSteward/ContentView.swift`
- Modify: `native/MacSoftwareSteward/Views/SharedComponents.swift`
- Modify: `native/MacSoftwareSteward/Views/UpdatesView.swift`
- Modify: other `native/MacSoftwareSteward/Views/*.swift` only when a compiler error or obvious spacing mismatch is caused by the new shared components.

**Interfaces:**
- Consumes all components from Tasks 1-4.
- Produces a clean build, passing native tests, and a concise manual QA note in the final response.

- [ ] **Step 1: Search for stale symbols and unused helpers**

Run:

```bash
rg -n "rowTint|rowBorder|scanningIcon|MaintenanceStatusPresenter|FlowingAccentLine|polishedTaskSurface" native/MacSoftwareSteward
```

Expected:
- `MaintenanceStatusPresenter`, `FlowingAccentLine`, and `polishedTaskSurface` have live references.
- `rowTint`, `rowBorder`, and `scanningIcon` have no references after Task 4 cleanup.

- [ ] **Step 2: Check color-theme restraint**

Run:

```bash
rg -n "purple|LinearGradient|\\.cyan|\\.blue|\\.orange|\\.green|\\.red" native/MacSoftwareSteward/ContentView.swift native/MacSoftwareSteward/Views/SharedComponents.swift native/MacSoftwareSteward/Views/UpdatesView.swift
```

Expected:
- Colors are attached to state roles, metrics, symbols, progress, selected navigation, or warnings.
- There is no full-window decorative gradient background.

- [ ] **Step 3: Run full automated verification**

Run:

```bash
npm test
npm run build
```

Expected:
- `npm test` ends with `All native tests passed.`
- `npm run build` creates `build/MacSoftwareSteward.app` without compiler errors.

- [ ] **Step 4: Optional local smoke run**

Run:

```bash
npm run open
```

Expected:
- The app launches.
- Sidebar status chip displays one of the presenter states.
- Main header shows the maintenance status band.
- `可升级` page renders the refined filter surface and update cards.
- Scanning state shows cyan status treatment and a flowing accent line.
- Reduced-motion systems still show static color/progress state without requiring motion to understand status.

- [ ] **Step 5: Commit final polish fixes**

```bash
git add native/MacSoftwareSteward native/MacSoftwareSteward/Views tests scripts
git commit -m "chore: verify ui effects upgrade"
```

Skip this commit when Step 1-4 do not produce additional file changes.

---

## Self-Review

**Spec coverage:** The plan covers the professional macOS control-console direction through shared surfaces, status band, sidebar refinement, update task cards, and state-driven motion. It keeps business logic unchanged, avoids new dependencies, respects reduced motion, and verifies through `npm test` and `npm run build`.

**Placeholder scan:** The plan contains no deferred implementation markers and every code-changing step includes concrete code or exact commands.

**Type consistency:** `MaintenanceStatusTintRole`, `MaintenanceStatusPresentation`, and `MaintenanceStatusPresenter.presentation(...)` are defined in Task 1 and consumed by Tasks 2 and 3. `FlowingAccentLine`, `StatusIconPlate`, and `polishedTaskSurface(tint:isActive:)` are defined in Task 2 and consumed by Tasks 3 and 4.
