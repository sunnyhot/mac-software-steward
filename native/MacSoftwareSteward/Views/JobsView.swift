import SwiftUI

private enum JobsPane: String, CaseIterable, Identifiable {
    case current = "任务"
    case history = "历史"

    var id: String { rawValue }
}

struct JobsView: View {
    @EnvironmentObject private var model: StewardModel
    @State private var selectedJobId: UUID?
    @State private var autoScroll = true
    @State private var selectedPane: JobsPane = .current

    var selectedJob: UpgradeJob? {
        let id = selectedJobId ?? model.jobs.first?.id
        return model.jobs.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("内容", selection: $selectedPane) {
                ForEach(JobsPane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            switch selectedPane {
            case .current:
                currentJobs
            case .history:
                MaintenanceHistoryContent(
                    historyStore: model.historyStore,
                    inspectionReportStore: model.inspectionReportStore
                )
            }
        }
        .onAppear {
            model.inspectionReportStore.reload()
            if model.jobs.isEmpty &&
                (!model.historyStore.records.isEmpty || !model.inspectionReportStore.reports.isEmpty) {
                selectedPane = .history
            }
        }
    }

    @ViewBuilder
    private var currentJobs: some View {
        if model.jobs.isEmpty {
            EmptyStateView(
                symbol: "terminal",
                title: "暂无任务",
                text: "升级操作会在这里显示日志。去「可升级」页面开始升级吧。"
            )
        } else {
            HStack(spacing: 0) {
                List(selection: $selectedJobId) {
                    ForEach(model.jobs) { job in
                        JobRow(job: job, isSelected: job.id == selectedJobId)
                            .tag(job.id)
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 340)

                Divider().opacity(0.5)

                if let job = selectedJob {
                    LogDetailView(job: job, autoScroll: $autoScroll)
                        .environmentObject(model)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(.regularMaterial)
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                )
                            Image(systemName: "terminal")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        Text("选择一个任务查看日志")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: - Job Row

private struct JobRow: View {
    var job: UpgradeJob
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator with subtle glow
            ZStack {
                if job.status == .running {
                    Circle()
                        .fill(statusColor(job.status).opacity(0.2))
                        .frame(width: 14, height: 14)
                }
                Circle()
                    .fill(statusColor(job.status))
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(job.label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(job.status.rawValue)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(statusColor(job.status))

                    if let finishedAt = job.finishedAt {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(finishedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let startedAt = job.startedAt {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(startedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(job.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !job.commands.isEmpty {
                    Text(job.commands.joined(separator: ", "))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Log Detail View

private struct LogDetailView: View {
    @EnvironmentObject private var model: StewardModel
    var job: UpgradeJob
    @Binding var autoScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)

                Text(job.label)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)

                Spacer()

                Badge(text: job.status.rawValue, color: statusColor(job.status))

                Button {
                    copyToPasteboard(fullLogText(job))
                } label: {
                    Label("复制日志", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(job.log.isEmpty)

                Button {
                    copyToPasteboard(failedCommand(job))
                } label: {
                    Label("复制命令", systemImage: "terminal")
                }
                .buttonStyle(.borderless)
                .disabled(job.status != .failed && job.status != .timedOut)

                if job.status == .running {
                    Button {
                        model.cancelJob(job.id)
                    } label: {
                        Label("取消任务", systemImage: "stop.circle")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    autoScroll.toggle()
                } label: {
                    Image(systemName: autoScroll ? "text.append" : "text.badge.xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(autoScroll ? Color.accentColor : .secondary)
                .help(autoScroll ? "自动滚动（已开启）" : "自动滚动（已关闭）")

            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial)

            Divider().opacity(0.5)

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(job.log) { line in
                            LogLineRow(line: line)
                                .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .font(.system(.body, design: .monospaced))
                .background(
                    ZStack {
                        Color(nsColor: .textBackgroundColor)
                            .opacity(0.3)
                        Color.clear
                    }
                )
                .onAppear {
                    scrollToBottom(proxy)
                }
                .onChange(of: job.log.count) {
                    if autoScroll {
                        scrollToBottom(proxy)
                    }
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let lastId = job.log.last?.id {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    private func fullLogText(_ job: UpgradeJob) -> String {
        job.log.map { "[\($0.stream)] \($0.text)" }.joined(separator: "\n")
    }

    private func failedCommand(_ job: UpgradeJob) -> String {
        job.log.reversed().first(where: { $0.stream == "command" })?.text.replacingOccurrences(of: "$ ", with: "") ?? job.commands.first ?? ""
    }
}

// MARK: - Log Line

private struct LogLineRow: View {
    var line: LogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Stream indicator with styled badge
            Text(streamLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(streamColor)
                .frame(width: 16, alignment: .center)

            // Log text
            Text(line.text)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
    }

    private var streamLabel: String {
        switch line.stream {
        case "stdout": return ">"
        case "stderr": return "!"
        case "command": return "$"
        case "system": return "*"
        default: return "·"
        }
    }

    private var streamColor: Color {
        switch line.stream {
        case "stdout": return .green.opacity(0.7)
        case "stderr": return .red.opacity(0.7)
        case "command": return .accentColor.opacity(0.7)
        case "system": return .orange.opacity(0.7)
        default: return .secondary.opacity(0.5)
        }
    }

    private var textColor: Color {
        switch line.stream {
        case "stdout": return .primary
        case "stderr": return .red.opacity(0.9)
        case "command": return .accentColor
        case "system": return .secondary
        default: return .secondary
        }
    }
}

private struct MaintenanceHistoryContent: View {
    @ObservedObject var historyStore: UpgradeHistoryStore
    @ObservedObject var inspectionReportStore: InspectionReportStore

    @State private var kindFilter: HistoryKindFilter = .all
    @State private var statusFilter: HistoryStatusFilter = .all
    @State private var query = ""

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
        if historyStore.records.isEmpty && inspectionReportStore.reports.isEmpty {
            EmptyStateView(
                symbol: "clock.arrow.circlepath",
                title: "暂无历史记录",
                text: "升级、巡检和待处理事项的处理结果会保存在这里。"
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    historyFilterBar

                    if entries.isEmpty {
                        EmptyStateView(
                            symbol: "line.3.horizontal.decrease.circle",
                            title: "没有匹配的历史",
                            text: "调整分类、状态或搜索词后再查看。"
                        )
                    } else {
                        ForEach(entries) { entry in
                            MaintenanceHistoryRow(entry: entry)
                        }
                    }
                }
            }
        }
    }

    private var historyFilterBar: some View {
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

private struct MaintenanceHistoryRow: View {
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
                        .foregroundStyle(historyStatusColor(entry.status))

                    Text(entry.title)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)

                    Spacer()

                    Badge(text: entry.kind.title, color: .blue)
                    Badge(text: entry.status.title, color: historyStatusColor(entry.status))
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

private func historyStatusColor(_ status: HistoryEntryStatus) -> Color {
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
