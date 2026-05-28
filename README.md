     1|# Mac 软件管家
     2|
     3|一个只在本机运行的 macOS 软件扫描与升级工具。现在包含 SwiftUI 原生 macOS 应用，以及早期 Web 面板。
     4|
     5|## 原生 macOS 应用
     6|
     7|构建 `.app`：
     8|
     9|```bash
    10|npm run build:native
    11|```
    12|
    13|构建并打开：
    14|
    15|```bash
    16|npm run open:native
    17|```
    18|
    19|产物位置：
    20|
    21|```text
    22|build/MacSoftwareSteward.app
    23|```
    24|
    25|原生应用使用 SwiftUI + AppKit，不依赖本地 Web 服务。应用会在 Finder 启动环境中主动查找 `/opt/homebrew/bin` 与 `/usr/local/bin` 下的 `brew` / `mas`。
    26|
    27|## 功能覆盖
    28|
    29|第一版覆盖：
    30|
    31|- `/Applications`、`~/Applications`、系统应用目录中的 `.app` 扫描
    32|- Homebrew formula 与 cask 扫描
    33|- `brew outdated --json=v2` 可升级项检测，支持 `--greedy`
    34|- 可选的 Mac App Store 扫描与升级，依赖 `mas` CLI
    35|- `mas` CLI 缺失时可从原生 App Store 页自动执行 `brew install mas`
    36|- 单个软件手动升级与一键升级可管理来源
    37|- 任务日志与命令输出追踪
    38|- 每日巡检：通过用户级 LaunchAgent 定时扫描，发现可升级项后自动升级
    39|- 应用自更新：从 GitHub Releases 检查、下载、安装并重启应用
    40|
    41|## Web 面板运行
    42|
    43|```bash
    44|npm install
    45|npm run dev
    46|```
    47|
    48|打开 Vite 输出的本地地址，通常是：
    49|
    50|```text
    51|http://127.0.0.1:5173
    52|```
    53|
    54|API 只绑定到 `127.0.0.1:4317`。
    55|
    56|## 能自动升级什么
    57|
    58|| 来源 | 扫描 | 自动升级 |
    59|| --- | --- | --- |
    60|| Homebrew formula | 是 | 是，`brew upgrade <name>` |
    61|| Homebrew cask | 是 | 是，`brew upgrade --cask <name>` |
    62|| Mac App Store | 需要 `mas` | 是，`mas upgrade <app-id>` |
    63|| 普通 `.app` | 是 | 不通用，界面提供 Finder 定位后手动处理 |
    64|
    65|如果 `mas` CLI 未安装，但 Homebrew 可用，原生应用会显示“安装 mas CLI”按钮。安装任务会进入任务日志，成功后自动重新扫描。
    66|
    67|普通 `.app` 没有统一升级协议。很多应用使用 Sparkle、内置更新器或专有安装器，第一版不会伪造“自动升级”能力，避免误删或误装。
    68|
    69|## 应用自更新
    70|
    71|原生应用的“应用更新”页支持：
    72|
    73|- 启动时自动检查新版本
    74|- 手动检查 GitHub Release
    75|- 下载 `MacSoftwareSteward.zip`
    76|- 解压后替换当前 `.app`
    77|- 自动重启应用
    78|
    79|当前默认更新源：
    80|
    81|```text
    82|https://github.com/sunnyhot/mac-software-steward/releases/latest
    83|```
    84|
    85|Release 资产名必须包含：
    86|
    87|```text
    88|MacSoftwareSteward.zip
    89|```
    90|
    91|## 每日巡检
    92|
    93|原生应用的“每日巡检”页可以启用后台自动升级。启用后会写入用户级 LaunchAgent：
    94|
    95|```text
    96|~/Library/LaunchAgents/local.codex.MacSoftwareSteward.daily.plist
    97|```
    98|
    99|LaunchAgent 会每天唤起应用包内的 helper：
   100|
   101|```text
   102|MacSoftwareSteward.app/Contents/MacOS/MacSoftwareStewardAgent
   103|```
   104|
   105|巡检日志保存在：
   106|
   107|```text
   108|~/Library/Application Support/MacSoftwareSteward/daily-inspection.log
   109|```
   110|
   111|每日巡检会自动处理 Homebrew formula/cask，以及已安装 `mas` CLI 时的 Mac App Store 应用。普通 `.app` 仍然只扫描和提示，不做静默升级。
   112|
   113|## 测试与构建
   114|
   115|```bash
   116|npm test
   117|npm run build
   118|npm run build:native
   119|```
   120|