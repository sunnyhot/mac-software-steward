# Changelog

## v0.13.20 (2026-06-15)

### 高级诊断与发布收口

- **普通 App 诊断细节增强**：高级模式下展示更新源异常、无法确认版本、识别器、置信度、安装/可用版本、Feed URL 和建议处理动作。
- **厂商更新器规则补充**：普通 App 更新能力识别新增 Chrome Keystone、Adobe、JetBrains Toolbox、Microsoft AutoUpdate 的 Info.plist 元数据证据。
- **规则/历史视图打磨**：规则页支持分类和搜索筛选，规则行可展开查看细节；历史页统一巡检、升级、待办处理记录，支持分类、状态和搜索筛选。
- **导入导出完善**：自动化数据 bundle 升级到 schema v2，纳入升级/待办历史；导入前展示策略、报告、历史数量，并兼容 schema v1 文件。
- **发布前收口**：版本号同步到 0.13.20，README 补充高级模式、导入导出和 package 流程说明。

## v0.12.0 (2026-05-28)

### 改进管理来源与下载更新的错误提示和恢复机制

- **管理来源报错展示可执行修复建议**：新增 SourceDiagnosticEngine 诊断引擎，自动分析 Homebrew/mas 错误并生成中文原因 + 建议操作；新增 ErrorRecoveryCard 通用恢复组件，支持重新扫描、安装工具、查看手动命令等一键操作
- **自更新下载失败保留失败态**：下载/解压/安装失败时保留失败状态，不再静默回退到发现新版本；新增 friendlyUpdateErrorMessage 友好错误翻译，网络/取消/超时等场景显示中文提示；弹窗与设置页同步展示失败信息和重试入口
- **集成验证通过**：管理来源错误提示与自更新失败恢复机制代码集成无冲突，构建验证通过

### 涉及子 issue

- [LUC-241] 管理来源报错展示可执行修复建议与自动处理入口
- [LUC-242] 自更新下载失败保留失败态并及时提示错误
- [LUC-243] 统一验证管理来源与自更新错误提示流程

# Changelog

## v0.9.2 (2026-05-22)

### UI 优化

- **整体布局专业化重构**：主窗口视觉基线统一，全应用采用 .regularMaterial 背景、.rounded 字体、12pt/10pt 圆角规范
- **组件化提取**：HeaderButton、MetricCard、SettingsDivider、JobNoticeIcon 等可复用组件
- **macOS 版本适配**：symbolEffect(.pulse/.rotate) 等 macOS 15+ API 添加 #available 守卫，兼容 macOS 14
- **动效细节打磨**：hover 缩放、spring 动画参数优化，克制且有质感
- **四个页面全部覆盖**：UpdatesView（可升级列表）、ApplicationsView（本机应用）、SourcesView（管理来源）、JobsView（任务日志）+ SettingsView（设置页）+ ContentView（主框架）

### 涉及子 issue

- [LUC-210] 主窗口布局与视觉基线
- [LUC-211] 可升级与本机应用列表信息架构
- [LUC-212] 管理来源与设置页面板体验
- [LUC-213] 任务日志与动效细节

## v0.9.1 (2026-05-21)

### 新功能

- **开机自启动时自动隐藏 Dock 图标**：应用通过开机自启动方式启动时，自动读取设置中的 Dock 图标显示偏好。若用户已设置不显示 Dock 图标，则在自启动完成后自动隐藏，无需用户手动触发。（[LUC-190]）

### 基础设施

- **GitHub Actions Release 工作流**：添加 CI/CD 自动发布工作流

### 涉及子 issue

- [LUC-190] 实现 AppDelegate 提前设置 Dock 策略 + 启动时隐藏窗口

## v0.9.0 (2026-05-20)

### 性能优化

- **ContentView 拆分**：将 1618 行巨型视图拆分为独立视图文件（UpdatesView/AppsView/JobsView/LogView/SettingsView），改善 SwiftUI 渲染性能
- **扫描进度指示**：扫描期间显示当前阶段（本机应用/Homebrew/App Store），改善等待体验
- **搜索防抖**：200ms 防抖避免每次按键全量过滤，cachedUpgradeablePackages 和 availableUpdates 从 computed property 改为 @Published 缓存
- **Brew 扫描超时隔离**：各 brew 子命令独立超时（30s），单个失败不阻塞其他结果
- **JobsView 日志优化**：LazyVStack 逐行渲染，1500 条日志不卡顿
- **classify 算法优化**：O(apps × casks) → O(apps + casks)，normalizeToken 正则结果缓存

### 涉及子 issue
- [LUC-146] 扫描进度指示
- [LUC-147] ContentView 拆分
- [LUC-148] 搜索防抖 + 缓存 computed property
- [LUC-149] Brew 扫描超时独立处理
- [LUC-150] JobsView 日志 LazyVStack 优化
- [LUC-151] classify 算法优化 + normalizeToken 缓存

## [0.12.1] - 2026-05-29

### Fixed
- 添加完整 codesign 签名步骤到 build-native.sh，修复 macOS 应用「租车总成本比较」打开报错"可能已损坏或不完整"的问题 (LUC-251)
  - Sparkle.framework ad-hoc 签名
  - codesign --deep --force --sign - 整包签名
  - codesign --verify --deep --strict 验证
  - xattr -cr 清除隔离属性
