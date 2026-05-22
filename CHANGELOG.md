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
