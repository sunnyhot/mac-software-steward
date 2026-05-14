# AGENTS.md — Mac 软件管家 (mac-software-steward)

## 项目简介

原生 macOS 应用，扫描本机软件并管理升级。覆盖 `/Applications`、Homebrew（formula/cask）、Mac App Store（通过 mas CLI）。SwiftUI + AppKit，arm64-only，macOS 14.0+。无 Xcode 项目文件，纯 `swiftc` 命令行编译。

- **Bundle ID**: `local.codex.MacSoftwareSteward`
- **版本**: 0.3.4（硬编码在 `package.json` + `Info.plist`，需同步更新）
- **GitHub 仓库**: `sunnyhot/mac-software-steward`

## 文件结构

### 主应用 (`native/MacSoftwareSteward/`)

| 文件 | 行数 | 职责 |
|------|------|------|
| `App.swift` | 137 | `@main` 入口，WindowGroup + MenuBarExtra，初始化 StewardModel/AppUpdateModel/LaunchAtLoginModel |
| `Models.swift` | 275 | 全部数据模型：AppItem, BrewPackage, MasApp, ScanResult, UpgradeJob, LogLine, UpdatablePackage 枚举等 |
| `Scanner.swift` | 440 | `SoftwareScanner`：并发扫描 Applications（system_profiler 优先，find 兜底）、Homebrew、mas；解析 outdated JSON；classify 关联 .app 与管理来源 |
| `CommandRunner.swift` | 268 | `Process` 封装：run（带超时）、runStreaming（实时输出回调）、commandPath（PATH 查找），线程安全锁 LockedOutput/FinishGate/LockedRecentOutput |
| `StewardModel.swift` | 506 | `@MainActor ObservableObject` 核心 ViewModel：扫描调度、单个/一键升级、任务队列（UpgradeJob）、失败分析（knownFailureHint）、每日巡检控制、packageProgress 跟踪 |
| `ContentView.swift` | 1132 | 全部 SwiftUI 视图：NavigationSplitView 五 Tab（可升级/本机应用/管理来源/设置/任务日志）、各种 Row/Badge/Progress 组件 |
| `AppUpdater.swift` | 417 | `AppUpdateModel`：GitHub Release API 检查/下载/解压（ditto -x -k）/覆盖安装/重启；自动检查周期 4h；fallback 用 redirect 解析 |
| `LaunchAtLoginModel.swift` | 54 | `SMAppService.mainApp` 开机启动注册/注销 |
| `DailyInspectionScheduler.swift` | 162 | 用户级 LaunchAgent plist 生成与 launchctl bootstrap/bootout；helper 路径指向 bundle 内 MacSoftwareStewardAgent |

### 后台巡检 Agent (`native/MacSoftwareStewardAgent/`)

| 文件 | 行数 | 职责 |
|------|------|------|
| `AgentMain.swift` | 81 | 独立命令行 `@main`：接收 `daily-check [--auto-upgrade] [--greedy] [--brew-update]`，扫描后执行 brew upgrade / mas upgrade，无 GUI |

### 构建与发布脚本 (`scripts/`)

| 文件 | 行数 | 职责 |
|------|------|------|
| `build-native.sh` | 44 | 清理 → 生成图标 → 两轮 swiftc（主应用 + Agent）→ codesign ad-hoc |
| `generate-app-icon.swift` | 177 | 纯代码绘制 AppIcon（NSBezierPath），输出 iconset + iconutil 生成 .icns |
| `package-release.sh` | 34 | 构建 → ditto 打 zip → sha256 → 生成 RELEASE_NOTES.md |
| `release-github.sh` | 66 | git push → gh release create/upload，支持 GITHUB_OWNER/GITHUB_REPO/GITHUB_VISIBILITY 环境变量 |

### 配置文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `package.json` | 12 | 版本号 + npm scripts 别名 |
| `native/Info.plist` | 40 | Bundle 元数据、GitHub Release 配置（Owner/Repo/AssetName/BundleName） |

## 架构与数据流

```
App.swift (@main)
  ├─ StewardModel (核心状态)
  │   ├─ SoftwareScanner.scanAll()
  │   │   ├─ scanApplications() → system_profiler -json → 解码 SystemProfilerApp
  │   │   ├─ scanBrew() → brew list/outdated → 合并
  │   │   ├─ scanMas() → mas list/outdated → 合并
  │   │   └─ classify() → 关联 .app 与 brew-cask/mas
  │   ├─ upgrade()/upgradeAll() → CommandRunner.runStreaming() → UpgradeJob 日志
  │   └─ DailyInspectionScheduler → LaunchAgent → MacSoftwareStewardAgent (独立进程)
  ├─ AppUpdateModel (自更新)
  │   └─ GitHub API → 下载 zip → ditto 解压 → zsh 脚本替换 .app → 重启
  └─ LaunchAtLoginModel (SMAppService)
ContentView.swift (所有视图)
  └─ EnvironmentObject 注入 model/updater/launchAtLogin
```

**Agent 编译共享文件**: `CommandRunner.swift` + `Models.swift` + `Scanner.swift` 被主应用和 Agent 同时编译。

## 构建命令

```bash
# 完整构建（生成 build/MacSoftwareSteward.app）
npm run build
# 等价于
bash scripts/build-native.sh

# 构建并打开
npm run open

# 打包 release（构建 + zip + sha256）
npm run package

# 发布到 GitHub（构建 + git push + gh release create）
npm run release
```

### 编译细节

**主应用**:
```bash
xcrun swiftc -O -target arm64-apple-macosx14.0 \
  -framework SwiftUI -framework AppKit \
  native/MacSoftwareSteward/*.swift \
  -o build/MacSoftwareSteward.app/Contents/MacOS/MacSoftwareSteward
```

**Agent**（无 SwiftUI/AppKit）:
```bash
xcrun swiftc -O -target arm64-apple-macosx14.0 \
  native/MacSoftwareSteward/CommandRunner.swift \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/Scanner.swift \
  native/MacSoftwareStewardAgent/*.swift \
  -o build/MacSoftwareSteward.app/Contents/MacOS/MacSoftwareStewardAgent
```

## 关键约定

1. **版本号双写**: 改版本时同时改 `package.json` 的 `version` 和 `native/Info.plist` 的 `CFBundleShortVersionString`
2. **无 Xcode 工程**: 没有 `.xcodeproj`/`.xcworkspace`，所有编译通过 `swiftc` 直接命令行
3. **PATH 硬编码**: `CommandRunner.defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"`，确保 Finder 启动环境能找到 brew/mas
4. **@MainActor**: StewardModel、AppUpdateModel、LaunchAtLoginModel 全部 `@MainActor`
5. **EnvironmentObject 传递**: 三个 Model 通过 `.environmentObject()` 在 App → ContentView 全链路注入
6. **日志上限**: UpgradeJob.log 最多 1500 条，LockedRecentOutput 保留最近 40 行
7. **Brew token 校验**: `validateBrewToken` 用正则 `^[A-Za-z0-9][A-Za-z0-9@._+-]*$` 防注入
8. **Agent 不升 mas 缺失为致命错误**: Agent 中如果 mas 不可用只 warn 并跳过，不退出
9. **自更新安装脚本**: 用 `Process()` 启动独立 zsh 脚本，等待主进程退出后替换 .app 再 `open -n` 重启
10. **中文 UI / 英文代码**: 界面文字全中文，代码标识符全英文

## 关键外部依赖

| 依赖 | 用途 | 必须安装 |
|------|------|----------|
| Homebrew (`brew`) | formula/cask 扫描与升级 | 推荐 |
| `mas` CLI | Mac App Store 扫描与升级 | 可选（可在应用内安装） |
| `system_profiler` | 扫描 `/Applications` 下的 .app | 系统自带 |
| `gh` CLI | GitHub Release 发布 | 仅发布时 |
| Xcode CLI Tools (`xcrun swiftc`) | 编译 | 必须 |

## 已知坑点

1. **Finder 环境无 PATH**: 从 Finder/Dock 启动时 shell profile 不加载，所以 `CommandRunner` 硬编码 PATH；如果用户 brew 装在非标准路径会找不到
2. **system_profiler 超时**: 扫描大量应用时可能超过 120s，已设 timeout 但慢机器仍可能卡
3. **Cask auto_updates 反复出现**: 已处理——`upgradeable = false` 当 `kind == "cask" && autoUpdates`，但需要开启 `--greedy` 才能扫描到这类 cask
4. **codesign 是 ad-hoc**: `codesign --force --sign -`，没有开发者证书签名，分发时会触发 Gatekeeper
5. **自更新替换失败**: 如果应用在 App Translocation 路径下运行（从下载目录直接打开），会尝试移到 `/Applications`；如果权限不够则移到 `~/Applications`
6. **LaunchAgent helper 路径硬绑 bundle**: 如果手动移动 .app 位置，LaunchAgent 里的路径会失效，需重新启用每日巡检
7. **无单元测试**: 项目没有测试目录，`npm test` 未定义实际测试
8. **ContentView 超大**: 1132 行单文件，包含所有视图组件，修改时需注意不破坏其他 Tab
