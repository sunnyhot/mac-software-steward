# Changelog

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
