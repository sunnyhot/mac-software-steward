import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HistoryContentView(
            historyStore: model.historyStore,
            inspectionReportStore: model.inspectionReportStore
        )
        .onAppear {
            model.inspectionReportStore.reload()
        }
    }
}

private struct HistoryContentView: View {
    @ObservedObject var historyStore: UpgradeHistoryStore
    @ObservedObject var inspectionReportStore: InspectionReportStore

    var body: some View {
        if historyStore.records.isEmpty && inspectionReportStore.reports.isEmpty {
            EmptyStateView(
                symbol: "clock.arrow.circlepath",
                title: "暂无历史记录",
                text: "升级完成、失败恢复和后续巡检记录会保存在这里。"
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !inspectionReportStore.reports.isEmpty {
                        HistorySectionTitle(title: "巡检报告")
                        ForEach(inspectionReportStore.reports) { report in
                            InspectionReportRow(report: report)
                        }
                    }

                    if !historyStore.records.isEmpty {
                        HistorySectionTitle(title: "升级历史")
                            .padding(.top, inspectionReportStore.reports.isEmpty ? 0 : 8)
                        ForEach(historyStore.records) { record in
                            HistoryRecordRow(record: record)
                        }
                    }
                }
            }
        }
    }
}

private struct HistorySectionTitle: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }
}

private struct InspectionReportRow: View {
    var report: InspectionReportRecord

    private var statusColor: Color {
        report.status == .succeeded ? .green : .orange
    }

    private var statusSymbol: String {
        report.status == .succeeded ? "checkmark.circle" : "exclamationmark.triangle"
    }

    private var scanText: String {
        let homebrewCount = report.scanSummary.brewFormulae + report.scanSummary.brewCasks
        return "应用 \(report.scanSummary.applications)，Homebrew \(homebrewCount)，MAS \(report.scanSummary.masApps)，可操作 \(report.scanSummary.actionable)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)

                Text(report.trigger.title)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)

                Spacer()

                Badge(text: report.status.title, color: statusColor)
            }

            Text(scanText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(report.startedAt, style: .date)
                Text(report.startedAt, style: .time)
                Text("自动 \(report.automaticUpgrades.count)")
                Text("跳过 \(report.skippedItems.count)")
                if !report.failures.isEmpty {
                    Text("失败 \(report.failures.count)")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct HistoryRecordRow: View {
    var record: UpgradeHistoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: record.status == "完成" ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(record.status == "完成" ? .green : .orange)

                Text(record.label)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)

                Spacer()

                Badge(text: record.status, color: record.status == "完成" ? .green : .orange)
            }

            Text(record.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let startedAt = record.startedAt {
                    Text(startedAt, style: .date)
                    Text(startedAt, style: .time)
                }
                if let exitCode = record.exitCode {
                    Text("退出码 \(exitCode)")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
