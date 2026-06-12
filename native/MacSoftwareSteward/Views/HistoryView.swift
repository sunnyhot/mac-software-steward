import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        if model.historyStore.records.isEmpty {
            EmptyStateView(
                symbol: "clock.arrow.circlepath",
                title: "暂无历史记录",
                text: "升级完成、失败恢复和后续巡检记录会保存在这里。"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.historyStore.records) { record in
                        HistoryRecordRow(record: record)
                    }
                }
            }
        }
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
