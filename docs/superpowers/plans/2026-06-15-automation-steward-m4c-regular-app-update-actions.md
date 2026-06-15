# Automation Steward M4c Regular App Update Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface concrete manual actions for ordinary `.app` update capabilities, including opening the app, opening known vendor updater apps when present, and revealing the app in Finder.

**Architecture:** Extend `AppUpdateCapability` with structured local action metadata, keep detector logic pure, add a small `RegularAppUpdateActionResolver` for known updater path candidates, then let `StewardModel` execute actions through `NSWorkspace`. `ApplicationsView` renders icon-only action buttons from the capability actions without adding network checks or automatic installs.

**Tech Stack:** Swift Foundation, SwiftUI, AppKit `NSWorkspace`, existing `swiftc` single-file tests.

---

## Scope Check

This plan implements M4c only:

- Add structured action metadata to `AppUpdateCapability`.
- Return detector-specific actions for Sparkle, Chrome, Adobe, JetBrains, Microsoft and unknown updaters.
- Resolve known local updater app candidates for Adobe, JetBrains and Microsoft.
- Render action buttons in the Applications list.
- Execute local actions through `StewardModel` with existing error banner fallback.

This plan does not implement vendor online version checks, appcast signature validation, app download/install, notification delivery, or silent `.app` replacement.

## File Structure

- Modify `native/MacSoftwareSteward/Models.swift`: add `AppUpdateActionKind`, `AppUpdateAction`, and `actions` on `AppUpdateCapability`.
- Modify `native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift`: populate local actions for each detector.
- Create `native/MacSoftwareSteward/RegularAppUpdateActionResolver.swift`: known updater app path candidates and first-existing lookup.
- Modify `native/MacSoftwareSteward/StewardModel.swift`: execute `AppUpdateAction` for an `AppItem`.
- Modify `native/MacSoftwareSteward/Views/ApplicationsView.swift`: render action buttons from `app.updateCapability.actions`.
- Modify `scripts/build-native.sh`: include resolver in Agent build only if needed by shared sources.
- Modify `scripts/test-native.sh`: add tests and source dependencies.
- Create `tests/RegularAppUpdateActionResolverTest.swift`.
- Update `tests/RegularAppUpdateDiscoveryTest.swift`.

---

### Task 1: Capability Actions From Detection

**Files:**
- Modify: `native/MacSoftwareSteward/Models.swift`
- Modify: `native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift`
- Test: `tests/RegularAppUpdateDiscoveryTest.swift`

- [ ] **Step 1: Extend the failing detector test**

In `tests/RegularAppUpdateDiscoveryTest.swift`, add after the Sparkle assertions:

```swift
        precondition(sparkleCapability.actions.map(\.kind) == [.openApp, .revealInFinder])
```

Change the Chrome assertion block to:

```swift
        let chromeCapability = RegularAppUpdateDiscovery.discover(appPath: chrome.path)
        precondition(chromeCapability.detector == .chromeKeystone)
        precondition(chromeCapability.actions.map(\.kind) == [.openApp, .revealInFinder])
```

Change the Microsoft assertion block to:

```swift
        let microsoftCapability = RegularAppUpdateDiscovery.discover(appPath: microsoft.path)
        precondition(microsoftCapability.detector == .microsoftAutoUpdate)
        precondition(microsoftCapability.actions.map(\.kind) == [.openUpdater, .openApp, .revealInFinder])
```

- [ ] **Step 2: Run the detector test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift \
  tests/RegularAppUpdateDiscoveryTest.swift \
  -o build/RegularAppUpdateDiscoveryTest
```

Expected: FAIL with `value of type 'AppUpdateCapability' has no member 'actions'`.

- [ ] **Step 3: Add action models**

In `native/MacSoftwareSteward/Models.swift`, add before `AppUpdateCapability`:

```swift
enum AppUpdateActionKind: String, Codable, Hashable {
    case openApp
    case openUpdater
    case revealInFinder
}

struct AppUpdateAction: Codable, Hashable {
    var kind: AppUpdateActionKind
    var title: String
    var systemImage: String
}
```

Add to `AppUpdateCapability` before `diagnostic`:

```swift
    var actions: [AppUpdateAction] = []
```

Update `.none` to set `actions: []`.

- [ ] **Step 4: Populate actions in detection**

In `native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift`, add helper methods:

```swift
    private static func actions(for detector: AppUpdateDetectorKind) -> [AppUpdateAction] {
        switch detector {
        case .adobeUpdater, .jetBrainsToolbox, .microsoftAutoUpdate:
            return [
                AppUpdateAction(kind: .openUpdater, title: "打开更新器", systemImage: "arrow.down.app"),
                AppUpdateAction(kind: .openApp, title: "打开应用", systemImage: "play.circle"),
                AppUpdateAction(kind: .revealInFinder, title: "Finder", systemImage: "arrow.up.forward.app")
            ]
        case .sparkle, .chromeKeystone, .unknownUpdater:
            return [
                AppUpdateAction(kind: .openApp, title: "打开应用", systemImage: "play.circle"),
                AppUpdateAction(kind: .revealInFinder, title: "Finder", systemImage: "arrow.up.forward.app")
            ]
        case .none:
            return []
        }
    }
```

Set `actions: actions(for: detector)` in every non-`.none` `AppUpdateCapability` initializer.

- [ ] **Step 5: Run the detector test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift \
  tests/RegularAppUpdateDiscoveryTest.swift \
  -o build/RegularAppUpdateDiscoveryTest
./build/RegularAppUpdateDiscoveryTest
```

Expected: command exits with status 0.

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/Models.swift native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift tests/RegularAppUpdateDiscoveryTest.swift
git commit -m "feat: add regular app update actions"
```

---

### Task 2: Known Updater Resolver

**Files:**
- Create: `native/MacSoftwareSteward/RegularAppUpdateActionResolver.swift`
- Test: `tests/RegularAppUpdateActionResolverTest.swift`

- [ ] **Step 1: Write the failing resolver test**

Create `tests/RegularAppUpdateActionResolverTest.swift`:

```swift
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
```

- [ ] **Step 2: Run the resolver test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  tests/RegularAppUpdateActionResolverTest.swift \
  -o build/RegularAppUpdateActionResolverTest
```

Expected: FAIL with `cannot find 'RegularAppUpdateActionResolver' in scope`.

- [ ] **Step 3: Add resolver**

Create `native/MacSoftwareSteward/RegularAppUpdateActionResolver.swift`:

```swift
import Foundation

enum RegularAppUpdateActionResolver {
    static func updaterPathCandidates(for detector: AppUpdateDetectorKind) -> [String] {
        switch detector {
        case .adobeUpdater:
            return [
                "/Applications/Utilities/Adobe Creative Cloud/ACC/Creative Cloud.app",
                "/Applications/Adobe Creative Cloud/Adobe Creative Cloud.app"
            ]
        case .jetBrainsToolbox:
            return [
                "/Applications/JetBrains Toolbox.app"
            ]
        case .microsoftAutoUpdate:
            return [
                "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app",
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app"
            ]
        case .none, .sparkle, .chromeKeystone, .unknownUpdater:
            return []
        }
    }

    static func firstExistingUpdaterPath(for detector: AppUpdateDetectorKind) -> String? {
        updaterPathCandidates(for: detector)
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}
```

- [ ] **Step 4: Run the resolver test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/RegularAppUpdateActionResolver.swift \
  tests/RegularAppUpdateActionResolverTest.swift \
  -o build/RegularAppUpdateActionResolverTest
./build/RegularAppUpdateActionResolverTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/RegularAppUpdateActionResolver.swift tests/RegularAppUpdateActionResolverTest.swift
git commit -m "feat: resolve regular app updater actions"
```

---

### Task 3: Execute And Show Update Actions

**Files:**
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `native/MacSoftwareSteward/Views/ApplicationsView.swift`

- [ ] **Step 1: Add action execution to model**

In `native/MacSoftwareSteward/StewardModel.swift`, add near `open(_ app:)`:

```swift
    func performUpdateAction(_ action: AppUpdateAction, for app: AppItem) {
        switch action.kind {
        case .openApp:
            open(app)
        case .revealInFinder:
            reveal(app)
        case .openUpdater:
            guard let path = RegularAppUpdateActionResolver.firstExistingUpdaterPath(for: app.updateCapability.detector) else {
                errorMessage = "未找到 \(app.updateCapability.detector.title) 更新器。"
                return
            }
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                if let error {
                    Task { @MainActor in
                        self.errorMessage = "打开更新器失败：\(error.localizedDescription)"
                    }
                }
            }
        }
    }
```

- [ ] **Step 2: Render action buttons from capability actions**

In `native/MacSoftwareSteward/Views/ApplicationsView.swift`, replace the current manual open app button:

```swift
                if app.updateCapability.hasManualAction && app.managedBy == "manual" {
                    Button {
                        model.open(app)
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("打开应用检查更新")
                }
```

with:

```swift
                if app.updateCapability.hasManualAction && app.managedBy == "manual" {
                    ForEach(app.updateCapability.actions, id: \.self) { action in
                        Button {
                            model.performUpdateAction(action, for: app)
                        } label: {
                            Image(systemName: action.systemImage)
                        }
                        .buttonStyle(.borderless)
                        .help(action.title)
                    }
                }
```

- [ ] **Step 3: Build to verify UI compiles**

Run:

```bash
npm run build
git restore native/Resources/AppIcon.iconset/*.png
```

Expected: app and Agent build, sign and verify successfully.

- [ ] **Step 4: Commit**

```bash
git add native/MacSoftwareSteward/StewardModel.swift native/MacSoftwareSteward/Views/ApplicationsView.swift
git commit -m "feat: run regular app update actions"
```

---

### Task 4: Build And Test Wiring

**Files:**
- Modify: `scripts/build-native.sh`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Add resolver to Agent build if needed**

`Scanner.swift` does not depend on `RegularAppUpdateActionResolver.swift`, so do not add it to the Agent compile command.

- [ ] **Step 2: Add resolver test to script**

In `scripts/test-native.sh`, add:

```bash
run_test RegularAppUpdateActionResolverTest \
  "$SRC/Models.swift" \
  "$SRC/RegularAppUpdateActionResolver.swift" \
  "$TESTS/RegularAppUpdateActionResolverTest.swift"
```

Add `"$SRC/RegularAppUpdateActionResolver.swift"` to `StewardModelScanGuardTest` because `StewardModel.swift` will reference it.

- [ ] **Step 3: Run full tests**

Run:

```bash
npm test
```

Expected: all native tests pass and output ends with `All native tests passed.`

- [ ] **Step 4: Commit**

```bash
git add scripts/test-native.sh
git commit -m "test: wire regular app action coverage"
```

---

### Task 5: Final Verification

**Files:**
- No source changes expected.

- [ ] **Step 1: Run full tests**

Run:

```bash
npm test
```

Expected: `All native tests passed.`

- [ ] **Step 2: Run full build**

Run:

```bash
npm run build
```

Expected: app build, Agent build, signing, signature verification and quarantine clearing all succeed.

- [ ] **Step 3: Clean build side effects and inspect status**

Run:

```bash
git restore native/Resources/AppIcon.iconset/*.png
git status --short
```

Expected: only the existing untracked `code-risk-scanner/` directory may appear and should not be staged.
