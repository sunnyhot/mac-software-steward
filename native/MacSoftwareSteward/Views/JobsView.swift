import SwiftUI

struct JobsView: View {
    @EnvironmentObject private var model: StewardModel
    @State private var selectedJobId: UUID?
    @State private var autoScroll = true

    var selectedJob: UpgradeJob? {
        let id = selectedJobId ?? model.jobs.first?.id
        return model.jobs.first { $0.id == id }
    }

    var body: some View {
        if model.jobs.isEmpty {
            EmptyStateView(
                symbol: "terminal",
                title: "暂无任务",
                text: "升级操作会在这里显示日志。去「可升级」页面开始升级吧。"
            )
        } else {
            HStack(spacing: 0) {
                // 任务列表
                List(selection: $selectedJobId) {
                    ForEach(model.jobs) { job in
                        JobRow(job: job, isSelected: job.id == selectedJobId)
                            .tag(job.id)
                    }

                    if !model.historyStore.records.isEmpty {
                        Section {
                            ForEach(model.historyStore.records.prefix(10)) { record in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.label)
                                        .font(.caption.bold())
                                    Text("\(record.status) · \(record.summary)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        } header: {
                            Text("历史记录")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 340)

                Divider().opacity(0.5)

                // 日志详情
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

                if !job.log.isEmpty {
                    Button {
                        let fullText = job.log.map { "[\($0.stream)] \($0.text)" }.joined(separator: "\n")
                        copyToPasteboard(fullText)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("复制全部日志")
                }
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
