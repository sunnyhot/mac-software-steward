import SwiftUI

// MARK: - Maintenance Overview View
//
// 维护总览页：应用启动后的默认页面。
// 回答四个问题：本机软件健康吗？什么可以自动处理？什么需要确认？上次维护发生了什么？
// 设计方向：System Diagnostic Bench——平静、克制、可信。
// 设计依据：docs/superpowers/specs/2026-07-10-unified-maintenance-engine-dashboard-design.md

struct MaintenanceOverviewView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    private var presentation: MaintenanceDashboardPresentation {
        let plan: MaintenancePlan? = {
            guard let scan = model.scan else { return nil }
            return MaintenancePlanner.makePlan(
                scan: scan,
                policyStore: model.policyStore,
                includeGreedy: model.includeGreedy,
                profile: automationProfile.profile
            )
        }()

        return MaintenanceDashboardPresenter.presentation(
            hasScanned: model.scan != nil,
            isScanning: model.isScanning,
            isExecuting: model.hasRunningJob,
            plan: plan,
            failedCount: model.packageProgress.values.filter {
                [.failed, .timedOut, .cancelled].contains($0.status)
            }.count,
            lastRun: nil,
            nextInspectionText: model.dailyInspectionEnabled ? "\(String(format: "%02d", model.dailyHour)):\(String(format: "%02d", model.dailyMinute))" : nil
        )
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                healthSection
                maintenanceTrackSection
                if presentation.health != .ready {
                    metricsSection
                }
                priorityTasksSection
                summarySection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Maintenance Track
    //
    // 维护轨道：扫描→评估→执行→校验，作为一条连续的视觉流程。
    // 当前阶段高亮，已完成的阶段标绿，未开始的阶段灰显。

    private var maintenanceTrackSection: some View {
        HStack(spacing: 0) {
            trackNode(title: "扫描", symbol: "magnifyingglass", state: trackState(for: .scanning))
            trackConnector(state: trackConnectorState(after: .scanning))
            trackNode(title: "评估", symbol: "chart.bar", state: trackState(for: .assessing))
            trackConnector(state: trackConnectorState(after: .assessing))
            trackNode(title: "执行", symbol: "arrow.triangle.2.circlepath", state: trackState(for: .executing))
            trackConnector(state: trackConnectorState(after: .executing))
            trackNode(title: "校验", symbol: "checkmark.shield", state: trackState(for: .verifying))
        }
        .padding(16)
        .polishedTaskSurface(tint: .secondary, isActive: presentation.health == .scanning || presentation.health == .executing)
    }

    private enum TrackPhase { case scanning, assessing, executing, verifying }

    private func trackState(for phase: TrackPhase) -> (color: Color, isActive: Bool, isDone: Bool) {
        let currentPhase: TrackPhase? = {
            switch presentation.health {
            case .scanning: return .scanning
            case .executing: return .executing
            case .ready, .allClear, .hasAutomatic, .needsConfirmation, .hasFailures: return nil
            }
        }()

        // 已扫描完成 = 扫描和评估都 done
        let hasScanned = presentation.health != .ready && presentation.health != .scanning

        let isCurrent = currentPhase == phase
        let isDone: Bool
        switch phase {
        case .scanning: isDone = hasScanned
        case .assessing: isDone = hasScanned
        case .executing: isDone = presentation.health == .allClear
        case .verifying: isDone = presentation.health == .allClear
        }

        let color: Color = isCurrent ? .accentColor : (isDone ? .green : .secondary)
        return (color, isCurrent, isDone)
    }

    private func trackConnectorState(after phase: TrackPhase) -> Color {
        trackState(for: phase).isDone ? .green : .secondary.opacity(0.3)
    }

    private func trackNode(title: String, symbol: String, state: (color: Color, isActive: Bool, isDone: Bool)) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(state.color.opacity(state.isActive ? 0.15 : 0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: state.isDone ? "checkmark" : symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(state.color)
            }
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(state.color)
        }
        .frame(maxWidth: .infinity)
    }

    private func trackConnector(state: Color) -> some View {
        Rectangle()
            .fill(state)
            .frame(height: 2)
            .frame(maxWidth: 40)
            .padding(.top, -14)
    }

    // MARK: - Health

    private var healthSection: some View {
        HStack(spacing: 16) {
            StatusIconPlate(
                symbol: presentation.healthSymbol,
                tint: tintColor(for: presentation.healthTintRole),
                isActive: presentation.health == .scanning || presentation.health == .executing
            )
            .scaleEffect(1.3)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.healthTitle)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(presentation.healthDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button {
                Task { await startSmartMaintenance() }
            } label: {
                Label("开始智能维护", systemImage: "bolt.fill")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!presentation.canStartSmartMaintenance)
        }
        .padding(16)
        .polishedTaskSurface(tint: tintColor(for: presentation.healthTintRole), isActive: presentation.health == .scanning || presentation.health == .executing)
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(presentation.metrics) { metric in
                MetricCardView(metric: metric)
            }
        }
    }

    // MARK: - Priority tasks

    @ViewBuilder
    private var priorityTasksSection: some View {
        if !presentation.priorityTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("优先任务")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 4)

                LazyVStack(spacing: 8) {
                    ForEach(presentation.priorityTasks) { task in
                        DashboardTaskRow(task: task)
                    }
                }
            }
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        if presentation.lastRunSummary != nil || model.dailyInspectionEnabled {
            VStack(alignment: .leading, spacing: 8) {
                Text("维护摘要")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 4)

                if let summary = presentation.lastRunSummary {
                    Label(summary, systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .polishedTaskSurface(tint: .secondary, isActive: false)
                }

                if model.dailyInspectionEnabled {
                    Label("每日巡检已启用：\(String(format: "%02d", model.dailyHour)):\(String(format: "%02d", model.dailyMinute))",
                          systemImage: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .polishedTaskSurface(tint: .secondary, isActive: false)
                }
            }
        }
    }

    // MARK: - Actions

    private func startSmartMaintenance() async {
        // 开始智能维护：先扫描，然后用 MaintenancePlanner 分类，自动执行 automatic 组。
        await model.scanSoftware(
            regularAppNetworkPolicy: automationProfile.profile.regularAppNetworkPolicy,
            notificationPolicy: automationProfile.profile.notificationPolicy
        )

        guard let scan = model.scan else { return }
        let plan = MaintenancePlanner.makePlan(
            scan: scan,
            policyStore: model.policyStore,
            includeGreedy: model.includeGreedy,
            profile: automationProfile.profile
        )

        // 只执行 automatic 组。
        guard plan.hasAutomatic else { return }

        var steps: [UpgradeStep] = []
        for item in plan.automaticItems {
            guard let package = item.package else { continue }
            do {
                let command = try await model.executor.command(for: package, includeGreedy: model.includeGreedy)
                steps.append(UpgradeStep(command: command, packageID: package.id, packageName: package.name))
            } catch {
                // command 构建失败（如 brew 不在 PATH），跳过该项，错误会在逐包升级时暴露。
                continue
            }
        }

        if !steps.isEmpty {
            model.executor.enqueueJob(
                label: "智能维护：自动升级 \(steps.count) 个低风险项",
                steps: steps,
                rescanAfterSuccess: true
            )
        }
    }
}

// tintColor(for:) 复用 SharedComponents.swift 中的全局实现。

// MARK: - Subviews

private struct MetricCardView: View {
    var metric: MaintenanceDashboardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: metric.symbol)
                    .foregroundStyle(tintColor(for: metric.tintRole))
                    .font(.system(size: 13))
                Text(metric.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(metric.textValue ?? "\(metric.value)")
                .font(.system(size: metric.textValue != nil ? 16 : 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .polishedTaskSurface(tint: tintColor(for: metric.tintRole), isActive: false)
    }
}

private struct DashboardTaskRow: View {
    var task: MaintenanceDashboardTaskRow

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: dispositionSymbol)
                .foregroundStyle(dispositionColor)
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 2) {
                Text(task.packageName)
                    .font(.system(size: 13, weight: .medium))
                Text(task.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Badge(text: task.disposition.title, color: dispositionColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .polishedTaskSurface(tint: dispositionColor, isActive: false)
    }

    private var dispositionColor: Color {
        switch task.disposition {
        case .automatic: return .accentColor
        case .confirmationRequired: return .orange
        case .reminderOnly: return .secondary
        case .blocked: return .red
        }
    }

    private var dispositionSymbol: String {
        switch task.disposition {
        case .automatic: return "bolt.circle"
        case .confirmationRequired: return "hand.raised"
        case .reminderOnly: return "bell"
        case .blocked: return "xmark.circle"
        }
    }
}
