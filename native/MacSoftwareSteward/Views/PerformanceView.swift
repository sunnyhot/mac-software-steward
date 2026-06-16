import SwiftUI

struct PerformanceView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        PerformanceContentView(store: model.scanPerformanceStore)
            .onAppear {
                model.scanPerformanceStore.reload()
            }
    }
}

private struct PerformanceContentView: View {
    @ObservedObject var store: ScanPerformanceStore

    private var records: [ScanPerformanceSnapshot] { store.records }
    private var latest: ScanPerformanceSnapshot? { records.first }
    private var summary: ScanPerformanceSummaryRow? { ScanPerformancePresenter.summary(for: records) }

    var body: some View {
        if records.isEmpty {
            EmptyStateView(
                symbol: "speedometer",
                title: "暂无性能记录",
                text: "完成一次扫描后，这里会显示阶段耗时、最近趋势和瓶颈提示。"
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let latest, let summary {
                        PerformanceSummaryPanel(snapshot: latest, summary: summary)
                        PerformancePhasePanel(snapshot: latest)
                        PerformanceDiagnosticPanel(snapshot: latest)
                    }
                    PerformanceRecentPanel(records: records)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

private struct PerformanceSummaryPanel: View {
    var snapshot: ScanPerformanceSnapshot
    var summary: ScanPerformanceSummaryRow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近扫描")
                .font(.system(.headline, design: .rounded))
            HStack(spacing: 10) {
                PerformanceMetric(title: "总耗时", value: summary.totalText, symbol: "timer")
                PerformanceMetric(title: "最慢阶段", value: summary.slowestPhaseTitle, symbol: "speedometer")
                PerformanceMetric(title: "扫描范围", value: summary.countSummary, symbol: "square.grid.2x2")
            }
            Text(summary.scannedAt.formatted(date: .abbreviated, time: .standard))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct PerformanceMetric: View {
    var title: String
    var value: String
    var symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct PerformancePhasePanel: View {
    var snapshot: ScanPerformanceSnapshot

    private var rows: [ScanPerformancePhaseRow] {
        ScanPerformancePresenter.phaseRows(for: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("阶段耗时")
                .font(.system(.headline, design: .rounded))
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label(row.title, systemImage: row.phase.symbol)
                            .font(.subheadline)
                        Spacer()
                        Text("\(row.durationText) · \(row.percentText)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(row.isSlowest ? .orange : .secondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(row.isSlowest ? Color.orange.opacity(0.75) : Color.accentColor.opacity(0.65))
                                .frame(width: max(4, proxy.size.width * row.fraction))
                        }
                    }
                    .frame(height: 7)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct PerformanceDiagnosticPanel: View {
    var snapshot: ScanPerformanceSnapshot

    private var hint: ScanPerformanceDiagnosticHint {
        ScanPerformancePresenter.diagnosticHint(for: snapshot)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: hint.symbol)
                .foregroundStyle(.orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(hint.title)
                    .font(.system(.headline, design: .rounded))
                Text(hint.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct PerformanceRecentPanel: View {
    var records: [ScanPerformanceSnapshot]

    private var rows: [ScanPerformanceRecentRow] {
        ScanPerformancePresenter.recentRows(for: records)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近扫描")
                .font(.system(.headline, design: .rounded))
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.scannedAt.formatted(date: .abbreviated, time: .standard))
                            .font(.subheadline)
                        Text(row.countSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(row.totalText)
                            .font(.system(.subheadline, design: .monospaced))
                        Text(row.slowestPhaseTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}
