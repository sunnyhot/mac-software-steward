import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("native/MacSoftwareSteward/Views", isDirectory: true)

do {
    try assertBodyStartsWithScrollView(
        sourceURL: root.appendingPathComponent("UpdatesView.swift"),
        viewName: "UpdatesView"
    )
    try assertBodyStartsWithScrollView(
        sourceURL: root.appendingPathComponent("ApplicationsView.swift"),
        viewName: "ApplicationsView"
    )
    try assertBodyStartsWithScrollView(
        sourceURL: root.appendingPathComponent("InboxView.swift"),
        viewName: "InboxView"
    )
    try assertBodyStartsWithScrollView(
        sourceURL: root.appendingPathComponent("SourcesView.swift"),
        viewName: "SourcesView"
    )
} catch {
    preconditionFailure("Tab scroll structure test failed: \(error)")
}

private func assertBodyStartsWithScrollView(sourceURL: URL, viewName: String) throws {
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    guard let structRange = source.range(of: "struct \(viewName): View"),
          let bodyRange = source[structRange.upperBound...].range(of: "var body: some View"),
          let bodyStart = source[bodyRange.upperBound...].firstIndex(of: "{") else {
        preconditionFailure("Could not find \(viewName).body in \(sourceURL.lastPathComponent)")
    }

    let bodyPrefix = source[source.index(after: bodyStart)...]
        .drop { $0.isWhitespace || $0.isNewline }
        .prefix(32)
    precondition(
        bodyPrefix.starts(with: "ScrollView"),
        "\(viewName).body should start with a page-level ScrollView, got: \(bodyPrefix)"
    )
}
