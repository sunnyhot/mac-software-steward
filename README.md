# Mac 软件管家

一个只在本机运行的 macOS 软件扫描与升级工具。当前主入口是 SwiftUI 原生 macOS 应用，负责扫描本机应用、Homebrew 包和 Mac App Store 应用，并提供升级、巡检与自更新能力。

## 原生 macOS 应用

构建 `.app`：

```bash
npm run build
# 等价别名
npm run build:native
```

构建并打开：

```bash
npm run open
# 等价别名
npm run open:native
```

产物位置：

```text
build/MacSoftwareSteward.app
```

原生应用使用 SwiftUI + AppKit，不依赖本地 Web 服务。应用会在 Finder 启动环境中主动查找 `/opt/homebrew/bin` 与 `/usr/local/bin` 下的 `brew` / `mas`。

## 功能覆盖

第一版覆盖：

- `/Applications`、`~/Applications`、系统应用目录中的 `.app` 扫描
- Homebrew formula 与 cask 扫描
- `brew outdated --json=v2` 可升级项检测，支持 `--greedy`
- 可选的 Mac App Store 扫描与升级，依赖 `mas` CLI
- `mas` CLI 缺失时可从原生 App Store 页自动执行 `brew install mas`
- 单个软件手动升级与一键升级可管理来源
- 任务日志与命令输出追踪
- 每日巡检：通过用户级 LaunchAgent 定时扫描，发现可升级项后自动升级
- 应用自更新：从 GitHub Releases 检查、下载、安装并重启应用

## 早期 Web 面板

项目早期包含过 Web 面板入口；当前 `package.json` 的脚本已收敛到原生应用、测试、打包与发布流程，不再把 Web 面板作为受支持的日常运行入口。需要恢复 Web 调试时，应先从 Git 历史确认对应前端和本地 API 代码仍然完整。

## 能自动升级什么

| 来源 | 扫描 | 自动升级 |
| --- | --- | --- |
| Homebrew formula | 是 | 是，`brew upgrade <name>` |
| Homebrew cask | 是 | 是，`brew upgrade --cask <name>` |
| Mac App Store | 需要 `mas` | 是，`mas upgrade <app-id>` |
| 普通 `.app` | 是 | 不通用，界面提供 Finder 定位后手动处理 |

如果 `mas` CLI 未安装，但 Homebrew 可用，原生应用会显示“安装 mas CLI”按钮。安装任务会进入任务日志，成功后自动重新扫描。

普通 `.app` 没有统一升级协议。很多应用使用 Sparkle、内置更新器或专有安装器，第一版不会伪造“自动升级”能力，避免误删或误装。

## 一键升级安全策略

一键升级会先生成升级计划，展示将执行的命令、来源、版本变化、风险标签与跳过原因。用户确认后才会执行选中的项目。

每个可管理软件可以设置升级策略：

- 自动升级：进入一键升级计划并允许每日巡检自动执行
- 确认后升级：进入一键升级计划，但每日巡检不会自动执行
- 仅提醒：显示更新，不默认执行
- 跳过：显示跳过原因，不进入自动执行

## 应用自更新

原生应用的“应用更新”页支持：

- 启动时自动检查新版本
- 手动检查 GitHub Release
- 下载 `MacSoftwareSteward.zip`
- 解压后替换当前 `.app`
- 自动重启应用

当前默认更新源：

```text
https://github.com/sunnyhot/mac-software-steward/releases/latest
```

Release 资产名必须包含：

```text
MacSoftwareSteward.zip
```

Release 清单中的 `sha256` 必须对应 `MacSoftwareSteward.zip`。客户端会在安装前校验下载文件，缺失或不匹配都会中止自更新。

## 每日巡检

原生应用的“每日巡检”页可以启用后台自动升级。启用后会写入用户级 LaunchAgent：

```text
~/Library/LaunchAgents/local.codex.MacSoftwareSteward.daily.plist
```

LaunchAgent 会每天唤起应用包内的 helper：

```text
MacSoftwareSteward.app/Contents/MacOS/MacSoftwareStewardAgent
```

巡检日志保存在：

```text
~/Library/Application Support/MacSoftwareSteward/daily-inspection.log
```

每日巡检会自动处理 Homebrew formula/cask，以及已安装 `mas` CLI 时的 Mac App Store 应用。普通 `.app` 仍然只扫描和提示，不做静默升级。

## 测试与构建

```bash
npm test
npm run build
npm run package
```

`scripts/build-native.sh` 会打印当前 Developer Dir、macOS SDK、Swift 和 Swift compiler 版本。如果看到 “SDK is not supported by the compiler”，说明本机 Swift 编译器与 macOS SDK 不匹配，需要通过 `xcode-select` 切换到匹配的 Xcode/Command Line Tools，或重新安装匹配版本的工具链。
