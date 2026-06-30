# Download Acceleration and Slow Download Recovery Design

## Context

Mac 软件管家 already runs several download-like workflows:

1. Homebrew formula/cask upgrades through `CommandRunner.runStreamingDetailed`.
2. `brew install mas` and daily inspection helper commands through the same command runner path.
3. Mac App Store upgrades through `mas upgrade`, also as an external command.
4. App self-update downloads through `AppUpdater` and `URLSessionDownloadDelegate`.
5. Manual app direct replacement downloads through `URLSession.shared.download(for:)`.

The current Homebrew cask path has the strongest progress signal: `HomebrewDownloadMonitor` watches Homebrew `.incomplete` cache files and estimates size, speed, and remaining time. `AppUpdater` also computes download progress and speed. Other download paths either inherit the process environment silently or do not expose enough progress to detect and recover from slow downloads.

The user wants fully automatic behavior: when downloads are slow, the app should choose practical acceleration or recovery actions by itself and finish faster where possible.

Current project constraints:

1. Native SwiftUI/AppKit app, no Xcode project; build and tests run through `npm test` and `npm run build`.
2. User-facing UI copy is Chinese; code identifiers stay English.
3. The app should not permanently change global system proxy, Homebrew config, or user shell files.
4. External tools such as `brew` and `mas` remain the actual installers for managed packages.
5. The implementation must avoid infinite retry loops and keep failure states understandable.

## Goals

- Add a shared download acceleration policy for app-owned downloads and app-launched external commands.
- Automatically detect usable acceleration routes from the current environment, macOS proxy settings, and common local proxy ports.
- Apply acceleration only to this app's URLSession requests and child processes unless the user explicitly changes system settings outside the app.
- Detect slow or stalled downloads using speed, byte growth, no-output duration, and expected remaining time where available.
- Automatically retry slow downloads with better acceleration context when retrying is safe.
- Preserve or clean partial downloads based on source-specific safety rules.
- Show concise status in existing progress cards and logs without asking the user to intervene.
- Keep the feature testable with pure policy tests and small integration tests.

## Non-Goals

- No permanent global proxy changes.
- No permanent Homebrew mirror rewrites in this pass.
- No third-party download accelerator dependency.
- No replacement of Homebrew, `mas`, Sparkle, or system installers.
- No remote telemetry.
- No unlimited retries.
- No promise that App Store downloads expose precise progress; `mas` can only be accelerated through environment and observed through command output/no-output timing.

## Proposed Architecture

Add a small shared acceleration layer:

```text
DownloadAccelerationPolicy
  -> discovers candidates
  -> ranks candidates
  -> builds per-attempt context
  -> classifies slow/stalled samples
  -> chooses retry actions

CommandRunner
  -> accepts optional environment overlay
  -> runs brew/mas/helper with acceleration context

AcceleratedDownloader
  -> URLSession download wrapper
  -> progress sampling
  -> automatic strategy retry

StewardModel/AppUpdater
  -> use the shared layer
  -> publish progress and recovery text
```

The policy layer is pure Swift logic where possible. It should not own UI state, start installs, or know package models. It only answers: which strategy should this attempt use, is the current transfer slow, and what is the next safe action?

## Acceleration Strategies

The first version should support these strategy types:

1. `direct`: no proxy override.
2. `inheritedProxy`: proxy variables already present in the app process environment.
3. `systemProxy`: proxy values read from macOS network proxy settings.
4. `localProxy`: common local proxy ports such as `127.0.0.1:7890`, `7897`, `1080`, `8080`, and `6152`.

Candidate validation should be lightweight:

- For HTTP(S) proxy candidates, run a short HEAD request or socket reachability check with a tight timeout.
- Prefer already configured environment or system proxy over guessing ports.
- Do not persist discovered proxy values as global configuration.
- Store only per-session ranking in memory.

For child processes, an acceleration attempt can inject:

```text
HTTP_PROXY
HTTPS_PROXY
ALL_PROXY
http_proxy
https_proxy
all_proxy
```

For URLSession downloads, configure `URLSessionConfiguration.connectionProxyDictionary` for the selected strategy.

## Slow Download Detection

Create a `DownloadSpeedSample` and `SlowDownloadDecision` model that can be used by both command-backed and URLSession-backed flows.

Signals:

- Current bytes downloaded.
- Expected byte count when available.
- Sample timestamp.
- Current speed in bytes per second.
- Seconds since last byte growth.
- Estimated remaining time.
- Attempt number and current strategy.

Default thresholds:

- Treat as slow after at least 45 seconds of observed download time.
- Treat as stalled after 30 seconds with no byte growth while the transfer is expected to be active.
- Treat as slow when speed remains below 256 KB/s for two consecutive samples.
- Treat as slow when expected remaining time is above 20 minutes for a package smaller than 1 GB.

Thresholds should live in one config struct so tests can use shorter values.

## Retry and Recovery Policy

Each download operation gets a bounded attempt plan:

1. Start with the best ranked strategy.
2. If slow or stalled, cancel the current attempt and retry with the next ranked strategy.
3. Preserve partial downloads by default when the source supports resume or cache reuse.
4. For Homebrew cask cache files, clear the matching `.incomplete` only when the file has not grown across the stall window or Homebrew reports an incomplete/corrupt download.
5. Stop after three strategy attempts or two destructive cache cleanups for a single package.
6. When all attempts are exhausted, keep the normal failure flow and show the best diagnostic gathered.

Command retries must happen at the step level, not by recursively starting a new user-visible job. The existing `UpgradeJob` should remain one logical task with log lines recording acceleration attempts.

## Command Integration

Extend `CommandRunner.run` and `runStreamingDetailed` to accept an optional environment overlay:

```swift
environmentOverlay: [String: String] = [:]
```

The final process environment remains based on `CommandRunner.processEnvironment()`, then applies the overlay.

`StewardModel` should wrap package step execution with an acceleration attempt loop for command types likely to download:

- `brew upgrade`
- `brew install`
- `mas upgrade`
- daily inspection helper commands

For Homebrew cask, continue using `HomebrewDownloadMonitor` for byte-level samples and add slow/stall classification. For formula and `mas`, use command output timing and known download parser output when available; if no download signal exists, do not kill aggressively until the no-output threshold is exceeded.

## URLSession Integration

Add `AcceleratedDownloader` for direct app downloads:

```swift
struct AcceleratedDownloadRequest {
    var url: URL
    var destinationFileName: String
    var expectedByteCount: Int64?
    var operationName: String
}
```

It should:

- Create a session per strategy attempt.
- Report progress samples through a callback.
- Retry automatically on slow/stall decisions, timeout, connection loss, and strategy-specific network errors.
- Return the final downloaded file URL.

`AppUpdater.download(asset:)` should use this wrapper instead of owning all download logic itself. `StewardModel.directlyReplace` should also use it so direct replacement downloads gain progress, speed, retry, and proxy strategy behavior.

## Homebrew-Specific Recovery

`HomebrewDownloadMonitor` should keep its current responsibility: locating matching `.incomplete` files and estimating progress. Add only narrow helpers if needed:

- Identify the matching incomplete file for a cask.
- Remove a matching incomplete file when the acceleration policy explicitly requests cleanup.

The cleanup path must be package-scoped. It must not clear the whole Homebrew downloads cache.

Log examples:

```text
下载速度持续偏低，正在切换加速方式重试。
已为本次命令临时使用系统代理。
检测到 Homebrew 缓存文件无增长，已清理当前 cask 的未完成下载后重试。
```

## UI and Status

Extend `PackageUpgradeProgress` with optional acceleration fields:

```swift
var accelerationStatusText: String?
var accelerationStrategyText: String?
var accelerationAttemptText: String?
```

Existing update cards should show a compact line while running:

```text
正在自动加速：切换到系统代理重试（第 2/3 次）
```

For App self-update, reuse the existing update dialog status area:

```text
下载偏慢，正在自动切换加速方式...
```

Manual direct replacement will publish acceleration status through existing model status/error messaging in this pass. It will not add a new per-app download progress panel.

## Settings

Default behavior should be enabled because the user wants fully automatic acceleration.

Add a small setting only if the implementation needs a user-facing kill switch:

```text
下载自动加速：开启/关闭
```

The first implementation can keep this in `AutomationProfile` or a small `UserDefaults` backed model if wiring it into profile export/import would create unnecessary scope. If the setting is added, default it to on.

## Data Flow

```text
User starts upgrade / daily check / self-update / direct replacement
  -> DownloadAccelerationPolicy ranks strategies
  -> Attempt starts with strategy environment/session config
  -> Progress samples feed SlowDownloadDecision
  -> If healthy: continue
  -> If slow/stalled and retry remains:
       cancel current attempt
       optionally clean source-scoped partial file
       retry with next strategy
  -> Success returns to existing install/verify flow
  -> Exhausted retries returns to existing failure handling with better diagnostic
```

## Error Handling

- Candidate probing failures only lower candidate rank; they should not fail an upgrade.
- Unknown proxy formats are ignored.
- A failed acceleration retry falls back to the next strategy or direct mode.
- If cancellation of a child process fails, wait for the existing command timeout path.
- If Homebrew cache cleanup fails, log it and retry without cleanup only if retry budget remains.
- If all acceleration strategies fail, keep existing recovery analysis and append the acceleration summary to logs.

## Testing Strategy

Use focused Swift single-file tests compatible with `scripts/test-native.sh`.

Add tests for:

- Strategy discovery and ranking from environment variables.
- Local proxy candidate formatting and validation result handling.
- Environment overlay merging in `CommandRunner`.
- Slow/stall decisions for low speed, no byte growth, high ETA, and healthy transfers.
- Retry planner stops after the configured attempt limit.
- Homebrew scoped cleanup chooses only the matching `.incomplete` file.
- `PackageUpgradeProgress` presenter copy includes acceleration status when present.
- `AcceleratedDownloader` retry behavior with an injected fake session/downloader, avoiding live network tests.

Update existing tests where needed:

- `HomebrewDownloadMonitorTest`
- `PackageProgressParserTest`
- `UpgradeProgressPresenterTest`
- `CommandRunnerControlTest`
- `AppUpdateSecurityTest` or a new `AppUpdaterDownloadAccelerationTest`

## Rollout Order

1. Add pure acceleration policy models and tests.
2. Add command environment overlay tests and implement `CommandRunner` overlay support.
3. Wire command-backed upgrades to use one acceleration attempt context without retries.
4. Add slow/stall classification for Homebrew cask monitor samples.
5. Implement bounded command retry for safe download phases.
6. Add `AcceleratedDownloader` and tests with injected fake transfer behavior.
7. Move `AppUpdater` downloads to `AcceleratedDownloader`.
8. Move direct replacement downloads to `AcceleratedDownloader`.
9. Add UI status text for package progress and self-update.
10. Run `npm test` and `npm run build`.

## Acceptance Criteria

- Homebrew, `mas`, app self-update, direct replacement, and daily helper commands can receive per-attempt acceleration context.
- The app detects slow or stalled downloads without user interaction.
- Slow Homebrew cask downloads automatically retry with alternate acceleration strategies.
- Homebrew cleanup is package-scoped and never deletes the entire downloads cache.
- URLSession-based downloads automatically retry with alternate strategies.
- The UI and task logs explain automatic acceleration attempts in Chinese.
- Retry attempts are bounded and cannot loop forever.
- No global system proxy, shell config, or Homebrew mirror is permanently changed.
- `npm test` passes.
- `npm run build` passes.
