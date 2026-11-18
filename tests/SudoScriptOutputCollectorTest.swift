import Foundation

@main
struct SudoScriptOutputCollectorTest {
    static func main() {
        let collector = SudoScriptOutputCollector()
        for commandIndex in 1...3 {
            for lineIndex in 0..<60 {
                collector.append(stream: "stdout", text: "command-\(commandIndex)-noise-\(lineIndex)")
            }
            let exitCode = commandIndex == 2 ? 1 : 0
            collector.append(stream: "stdout", text: "__RC_\(commandIndex)_\(exitCode)__")
        }

        precondition(collector.containsResultMarker)
        let captured = collector.text()
        precondition(captured.contains("__RC_1_0__"))
        precondition(captured.contains("__RC_2_1__"))
        precondition(captured.contains("__RC_3_0__"))
        let outcomes = SudoScriptParser.outcomes(in: captured, count: 3)
        precondition(outcomes.map(\.exitCode) == [0, 1, 0])
        precondition(!outcomes[0].outputSegment.contains("command-1-noise-0"))
        precondition(outcomes[0].outputSegment.contains("command-1-noise-59"))
        precondition(outcomes[1].outputSegment.contains("command-2-noise-59"))
        precondition(outcomes[2].outputSegment.contains("command-3-noise-59"))
        let lineCount = captured.split(whereSeparator: \.isNewline).count
        precondition(lineCount <= 3 * 40, "Output must stay bounded per command, got \(lineCount)")

        let noMarkers = SudoScriptOutputCollector()
        for index in 0..<50 {
            noMarkers.append(stream: "stderr", text: "line-\(index)")
        }
        precondition(!noMarkers.containsResultMarker)
        precondition(noMarkers.text().contains("line-49"))
        precondition(!noMarkers.text().contains("line-0"))
    }
}
