import SwiftUI

struct UpgradePlanView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var inboxStore: InboxStore
    @Environment(\.dismiss) private var dismiss

    private var selectedCount: Int {
        model.upgradePlanRows.filter { model.selectedPlanIDs.contains($0.packageID) && $0.canExecute }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("升级计划")
                    .font(.title2.bold())
                Spacer()
                Text("已选择 \(selectedCount) 项")
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(model.upgradePlanRows) { row in
                    UpgradePlanRowView(row: row)
                        .environmentObject(model)
                }
            }
            .frame(minHeight: 420)

            HStack {
                Button("全选可执行项") {
                    model.selectedPlanIDs = Set(model.upgradePlanRows.filter(\.canExecute).map(\.packageID))
                }
                .disabled(model.isConfirmingUpgradePlan)
                Button("清空选择") {
                    model.selectedPlanIDs.removeAll()
                }
                .disabled(model.isConfirmingUpgradePlan)
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .disabled(model.isConfirmingUpgradePlan)
                Button {
                    Task { await model.confirmUpgradePlan(inboxStore: inboxStore) }
                } label: {
                    Label(model.isConfirmingUpgradePlan ? "准备中" : "执行升级", systemImage: model.isConfirmingUpgradePlan ? "hourglass" : "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCount == 0 || model.isConfirmingUpgradePlan)
            }
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 560)
    }
}

private struct UpgradePlanRowView: View {
    @EnvironmentObject private var model: StewardModel
    var row: UpgradePlanRow

    private var isSelected: Bool {
        model.selectedPlanIDs.contains(row.packageID)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { model.setPlanSelection(row.packageID, selected: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(!row.canExecute || model.isConfirmingUpgradePlan)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(row.packageName)
                        .font(.headline)
                    Text(row.source)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                Text("\(versionText(row.installedVersion)) -> \(targetVersionText(row.currentVersion))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(row.commandDisplay)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)

                if !row.skipReason.isEmpty {
                    Text(row.skipReason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if !row.riskLabels.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(row.riskLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption2.bold())
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            Badge(text: row.riskLevel.title, color: riskColor(row.riskLevel))

            Text(row.policy.title)
                .font(.caption.bold())
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 6)
        .opacity(row.canExecute ? 1 : 0.7)
    }
}

private func targetVersionText(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "未知" : trimmed
}

private func riskColor(_ level: RiskLevel) -> Color {
    switch level {
    case .low: return .green
    case .medium: return .orange
    case .high: return .red
    }
}
