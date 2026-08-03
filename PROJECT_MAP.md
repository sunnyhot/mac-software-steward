# PROJECT_MAP.md — Mac 软件管家 (mac-software-steward)

## 项目简介

原生 macOS 应用，扫描本机软件并管理升级。覆盖 `/Applications`、Homebrew（formula/cask）和 Mac App Store（通过 `mas` CLI）。SwiftUI + AppKit，arm64-only，macOS 14.0+。仓库没有 Xcode 工程文件，构建由脚本直接调用 `xcrun swiftc`。

- **Bundle ID**: `local.codex.MacSoftwareSteward`
- **版本**: 0.17.0（`package.json` 与 `native/Info.plist` 需要同步）
- **GitHub 仓库**: `sunnyhot/mac-software-steward`

## 文件结构

### 主应用 (`native/MacSoftwareSteward/`)

| 文件 | 行数 | 职责 |
|------|------|------|
| `App.swift` | 约 280 | `@main` 入口、原生窗口/menu bar、命令菜单、全局 model 注入 |
| `ContentView.swift` | 约 430 | 应用主导航、原生工具栏与页面容器 |
| `Views/*.swift` | 约 4400 | 可升级、本机软件、设置和共享 UI 组件 |
| `Models.swift` | 约 419 | 扫描结果、包、任务、进度、策略等核心数据模型 |
| `StewardModel.swift` | 约 690 | `@MainActor ObservableObject` 核心 ViewModel，负责扫描、升级队列、进度、巡检状态与派生数据 |
| `SoftwareScanning.swift` | 约 12 | 扫描协议与线上实现，用于隔离 `StewardModel` 与扫描器并支持测试替身 |
| `Scanner.swift` | 约 742 | `SoftwareScanner`：扫描 Applications/Homebrew/mas，记录阶段耗时，缓存普通 App 更新能力，并有界并发检查 Sparkle appcast |
| `RegularAppUpdateDiscovery.swift` / `RegularAppUpdateDiscoveryCache.swift` | 约 415 | 普通 `.app` 更新能力识别和基于 `Info.plist` 元数据的本机缓存 |
| `ScanPerformance.swift` | 约 125 | 扫描阶段耗时模型，用于扫描结果和诊断日志，不单独持久化 |
| `CommandRunner.swift` | 约 398 | `Process` 封装，支持超时、流式输出、PATH 查找和并发安全输出收集 |
| `UpgradePlanner.swift` / `UpgradePolicyStore.swift` | 约 300 | 维护计划、包级策略、跳过原因和选择状态 |
| `MaintenanceExecutor.swift` | 约 1158 | 升级任务队列、并发执行、进度、下载加速与 sudo 批量提权的执行器 |
| `MaintenanceCommandResolver.swift` | 约 43 | 从 `MaintenanceExecutor` 提取的无状态命令解析（包→命令、token 校验、PATH 定位） |
| `MaintenanceFailureAnalyzer.swift` | 约 82 | 从 `MaintenanceExecutor` 提取的无状态失败分析（退出码/输出→摘要、建议、动作） |
| `UpgradeProgressPresenter.swift` / `PackageProgressParser.swift` | 约 251 | Homebrew/mas 输出解析与包级阶段展示 |
| `UpgradeFailureAnalyzer.swift` / `UpgradeVerifier.swift` | 约 161 | 升级失败解释与升级后状态校验 |
| `BrewCaskCleanupDetector.swift` | 约 53 | Cask 残留、覆盖冲突和清理动作识别 |
| `HomebrewDownloadMonitor.swift` / `HomebrewCaskDownloadSizeResolver.swift` | 约 220 | Homebrew 下载缓存监控、大小探测与下载进度估算 |
| `AppUpdater.swift` | 约 660 | GitHub Release 检查、manifest 解析、下载、解压、自更新安装调度 |
| `AppUpdateSecurity.swift` | 约 38 | 自更新 zip 的 SHA-256 校验 |
| `SelfUpdateInstallScript.swift` | 约 63 | 生成自更新安装脚本，使用临时 app 与备份 app 支持失败回滚 |
| `SourceDiagnostics.swift` | 约 147 | Homebrew/mas 来源诊断与恢复动作 |
| `DailyInspectionScheduler.swift` / `DailyUpgradePolicy.swift` | 约 171 | 用户级 LaunchAgent 生成、启停和每日自动升级策略 |
| `LaunchAtLoginModel.swift` | 约 53 | `SMAppService.mainApp` 开机启动注册/注销 |

### 后台巡检 Agent (`native/MacSoftwareStewardAgent/`)

| 文件 | 行数 | 职责 |
|------|------|------|
| `AgentMain.swift` | 约 101 | 独立命令行 `@main`，执行 `daily-check` 扫描和可选自动升级 |

### 构建、测试与发布 (`scripts/`, `.github/workflows/`)

| 文件 | 行数 | 职责 |
|------|------|------|
| `scripts/build-native.sh` | 约 107 | 清理、打印工具链、生成图标、编译主应用与 Agent、ad-hoc 签名、签名验证 |
| `scripts/test-native.sh` | 约 140 | 逐个用 `swiftc` 编译并运行 native 单文件测试 |
| `scripts/generate-app-icon.swift` | 约 176 | 代码绘制 AppIcon，生成 iconset 和 `.icns` |
| `scripts/package-release.sh` | 约 101 | 构建、zip、sha256、release notes、`latest.json` |
| `scripts/release-github.sh` | 约 68 | 推送 tag/commit 并通过 `gh release` 发布资产 |
| `.github/workflows/release.yml` | - | tag push release 流程，构建前执行 `npm test` |

### 测试 (`tests/`)

`tests/` 包含 Swift 单文件测试，覆盖应用外观、单实例策略、更新弹框、自更新安全、普通 App 更新诊断、历史展示、扫描防重入、升级策略/计划/历史、失败分析、下载监控、进度解析和升级校验等核心逻辑。

## 架构与数据流

```text
App.swift (@main)
  ├─ StewardModel (核心状态)
  │   ├─ SoftwareScanning → SoftwareScanner.scanAll()
  │   │   ├─ scanApplications() → system_profiler/find
  │   │   ├─ scanBrew() → brew list/outdated/info
  │   │   ├─ scanMas() → mas list/outdated
  │   │   └─ classify() → 关联 .app 与 brew-cask/mas
  │   ├─ UpgradePlanner + UpgradePolicyStore → 可确认的维护计划
  │   ├─ CommandRunner.runStreaming() → UpgradeJob + PackageProgress
  │   └─ DailyInspectionScheduler → LaunchAgent → MacSoftwareStewardAgent
  ├─ AppUpdateModel
  │   └─ GitHub Release/latest.json → 下载 zip → SHA-256 校验 → 解压 → 替换 .app
  └─ LaunchAtLoginModel
```

## 构建命令

```bash
# 测试
npm test

# 完整构建（生成 build/MacSoftwareSteward.app）
npm run build
npm run build:native

# 构建并打开
npm run open
npm run open:native

# 打包 release（构建 + zip + sha256 + latest.json）
npm run package

# 发布到 GitHub（构建 + git push + gh release create）
npm run release
```

## 编译细节

主应用编译：

```bash
xcrun swiftc -O -target arm64-apple-macosx14.0 \
  -sdk "$SDK_PATH" \
  -framework SwiftUI -framework AppKit \
  native/MacSoftwareSteward/*.swift \
  native/MacSoftwareSteward/Views/*.swift \
  -o build/MacSoftwareSteward.app/Contents/MacOS/MacSoftwareSteward
```

Agent 编译共享 `CommandRunner.swift`、`ScanPerformance.swift`、`Models.swift`、`RegularAppUpdateDiscovery.swift`、`RegularAppUpdateDiscoveryCache.swift`、`Scanner.swift`、升级策略相关文件和 `SoftwareScanning.swift`，再合并 `native/MacSoftwareStewardAgent/*.swift` 输出到 bundle 内。

`scripts/build-native.sh` 会在构建前打印 Developer Dir、SDK path/version、Swift 和 Swift compiler 版本。遇到 “this SDK is not supported by the compiler” 时，脚本会追加明确提示：当前 Swift compiler 与 macOS SDK 不匹配，需要切换或安装匹配的 Xcode/Command Line Tools。

## 关键约定

1. **版本号双写**: 改版本时同时改 `package.json` 的 `version` 和 `native/Info.plist` 的 `CFBundleShortVersionString`/`CFBundleVersion`
2. **无 Xcode 工程**: 没有 `.xcodeproj`/`.xcworkspace`，所有编译通过脚本直接调用 `swiftc`
3. **PATH 兜底**: `CommandRunner.defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"`，用于 Finder/Dock 启动环境
4. **主 actor 边界**: `StewardModel`、`AppUpdateModel`、`LaunchAtLoginModel` 和 `SoftwareScanning` 均按主 actor 使用
5. **自更新安全**: Release manifest 必须提供 zip 的 `sha256`；下载后先校验，再解压和替换
6. **自更新回滚**: 安装脚本先复制到临时 app，再备份旧 app，替换失败时恢复旧 app
7. **扫描防重入**: `StewardModel.scanSoftware()` 在已有扫描进行中时直接忽略重复触发，相关按钮会禁用
8. **Agent 非 GUI**: Agent 不依赖 SwiftUI/AppKit，`mas` 不可用时记录 warning 并跳过
9. **中文 UI / 英文代码**: 界面文字以中文为主，代码标识符保持英文

## 关键外部依赖

| 依赖 | 用途 | 必须安装 |
|------|------|----------|
| Homebrew (`brew`) | formula/cask 扫描与升级 | 推荐 |
| `mas` CLI | Mac App Store 扫描与升级 | 可选（可在应用内安装） |
| `system_profiler` | 扫描 `/Applications` 下的 `.app` | 系统自带 |
| `gh` CLI | GitHub Release 发布 | 仅发布时 |
| Xcode / Command Line Tools (`xcrun swiftc`) | 编译和测试 | 必须 |

## 已知坑点

1. **工具链必须匹配**: Swift compiler 与 macOS SDK 版本不匹配时，测试和构建都会在导入 Swift 标准库前失败
2. **Finder 环境无 PATH**: 从 Finder/Dock 启动时 shell profile 不加载，非标准 Homebrew 安装路径可能需要额外诊断
3. **system_profiler 可能较慢**: 大量应用或慢机器上扫描可能接近超时，代码保留 `find` 兜底
4. **Cask auto_updates 反复出现**: 自动更新型 cask 会显示但默认不进入自动升级，`--greedy` 会影响可见范围
5. **codesign 是 ad-hoc**: 本地构建使用 `codesign --force --sign -`，正式分发仍需考虑 Developer ID 与 notarization
6. **LaunchAgent helper 路径绑定 bundle**: 手动移动 `.app` 后，可能需要重新启用每日巡检来刷新 plist 路径
7. **`StewardModel.swift` 仍偏大**: 核心状态与升级调度集中在一个文件，后续可继续按扫描、升级、巡检拆分
