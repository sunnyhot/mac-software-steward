import SwiftUI

struct JobsView: View {
    @EnvironmentObject private var model: StewardModel
    @State private var selectedJobId: UUID?

    var selectedJob: UpgradeJob? {
        let id = selectedJobId ?? model.jobs.first?.id
        return model.jobs.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 14) {
            List(selection: $selectedJobId) {
                ForEach(model.jobs) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.label)
                            .font(.headline)
                        Text(job.status.rawValue)
                            .foregroundStyle(statusColor(job.status))
                            .font(.caption.bold())
                    }
                    .tag(job.id)
                }
            }
            .frame(width: 280)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "terminal")
                    Text(selectedJob?.label ?? "任务日志")
                        .font(.headline)
                    Spacer()
                    if let selectedJob {
                        Badge(text: selectedJob.status.rawValue, color: statusColor(selectedJob.status))
                    }
                }

                ScrollView {
                    Text(selectedJob?.log.map { "[\($0.stream)] \($0.text)" }.joined(separator: "\n") ?? "等待任务输出...")
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct JobNoticeView: View {
    @EnvironmentObject private var model: StewardModel
    var notice: JobNotice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notice.symbol)
                .symbolEffect(.pulse, options: .repeating, isActive: !notice.isFailure)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.bold())
                Text(notice.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
            if notice.isFailure {
                Button {
                    model.dismissFailureNotice()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Button {
                model.selectedTab = .jobs
            } label: {
                Label("查看日志", systemImage: "terminal")
            }
        }
        .padding(10)
        .foregroundStyle(notice.isFailure ? .red : .accentColor)
        .background((notice.isFailure ? Color.red : Color.accentColor).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
