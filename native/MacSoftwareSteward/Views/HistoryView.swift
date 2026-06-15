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

    @State private var kindFilter: HistoryKindFilter = .all
    @State private var statusFilter: HistoryStatusFilter = .all
    @State private var query = ""

    private var hasAnyHistory: Bool {
        !historyStore.records.isEmpty || !inspectionReportStore.reports.isEmpty
    }

    private var entries: [HistoryEntry] {
        HistoryPresenter.entries(
            reports: inspectionReportStore.reports,
            records: historyStore.records,
            kind: kindFilter,
            status: statusFilter,
            query: query
        )
    }

    var body: some View {
        if !hasAnyHistory {
            EmptyStateView(
                symbol: "clock.arrow.circlepath",
                title: "暂无历史记录",
                text: "升级完成、失败恢复和后续巡检记录会保存在这里。"
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    HistoryFilterBar(
                        kindFilter: $kindFilter,
                        statusFilter: $statusFilter,
                        query: $query
                    )

                    if entries.isEmpty {
                        EmptyStateView(
                            symbol: "line.3.horizontal.decrease.circle",
                            title: "没有匹配的历史",
                            text: "调整分类、状态或搜索词后再查看。"
                        )
                    } else {
                        ForEach(entries) { entry in
                            HistoryEntryRow(entry: entry)
                        }
                    }
                }
            }
        }
    }
}

private struct HistoryFilterBar: View {
    @Binding var kindFilter: HistoryKindFilter
    @Binding var statusFilter: HistoryStatusFilter
    @Binding var query: String

    var body: some View {
        HStack(spacing: 10) {
            TextField("搜索历史、命令、失败原因", text: $query)
                .textFieldStyle(.roundedBorder)

            Picker("分类", selection: $kindFilter) {
                ForEach(HistoryKindFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Picker("状态", selection: $statusFilter) {
                ForEach(HistoryStatusFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct HistoryEntryRow: View {
    var entry: HistoryEntry

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(entry.detailItems, id: \.self) { item in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: item.symbol)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 16)
                        Text(item.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 6)
            .padding(.leading, 26)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: entry.kind.symbol)
                        .foregroundStyle(statusColor(entry.status))

                    Text(entry.title)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)

                    Spacer()

                    Badge(text: entry.kind.title, color: .blue)
                    Badge(text: entry.status.title, color: statusColor(entry.status))
                }

                Text(entry.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(entry.timestamp, style: .date)
                    Text(entry.timestamp, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private func statusColor(_ status: HistoryEntryStatus) -> Color {
    switch status {
    case .succeeded:
        return .green
    case .failed:
        return .orange
    case .ignored:
        return .secondary
    case .pending:
        return .blue
    }
}
