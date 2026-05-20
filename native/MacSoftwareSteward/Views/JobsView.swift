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
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if let log = selectedJob?.log, !log.isEmpty {
                            ForEach(log) { line in
                                Text("[\(line.stream)] \(line.text)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(logLineColor(line.stream))
                                    .textSelection(.enabled)
                            }
                        } else {
                            Text("等待任务输出...")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
