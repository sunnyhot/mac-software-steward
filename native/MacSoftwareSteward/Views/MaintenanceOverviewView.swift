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
                metricsSection
                priorityTasksSection
                summarySection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 4)
        }
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
            Text("\(metric.value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
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
