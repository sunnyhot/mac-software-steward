import Foundation

@main
struct SudoScriptParserTest {
    static func main() {
        // --- 正常三段：成功/失败/成功，输出片段归属正确 ---
        let output = """
        ==> upgrading pkgA
        some brew stdout for A
        __RC_1_0__
        ==> upgrading pkgB
        error line for B
        __RC_2_1__
        ==> upgrading pkgC
        ok line for C
        __RC_3_0__
        """
        let outcomes = SudoScriptParser.outcomes(in: output, count: 3)
        precondition(outcomes.count == 3, "expected 3 outcomes, got \(outcomes.count)")

        precondition(outcomes[0].packageIndex == 1, "first outcome is pkgA (index 1)")
        precondition(outcomes[0].exitCode == 0, "pkgA exit 0")
        precondition(outcomes[0].outputSegment.contains("some brew stdout for A"), "pkgA segment content")
        precondition(!outcomes[0].outputSegment.contains("__RC_"), "segment must not contain its own marker")

        precondition(outcomes[1].packageIndex == 2, "second outcome is pkgB (index 2)")
        precondition(outcomes[1].exitCode == 1, "pkgB exit 1 (failure)")
        precondition(outcomes[1].outputSegment.contains("error line for B"), "pkgB segment content")

        precondition(outcomes[2].packageIndex == 3, "third outcome is pkgC (index 3)")
        precondition(outcomes[2].exitCode == 0, "pkgC exit 0")
        precondition(outcomes[2].outputSegment.contains("ok line for C"), "pkgC segment content")

        // --- 中段失败不影响前后段解析（失败隔离验证） ---
        precondition(outcomes[0].exitCode == 0 && outcomes[2].exitCode == 0, "neighbors of failed pkgB must still parse independently")

        // --- 缺失标记：该包用哨兵值，其余正常 ---
        let partial = """
        __RC_1_0__
        __RC_3_0__
        """
        let partialOutcomes = SudoScriptParser.outcomes(in: partial, count: 3)
        precondition(partialOutcomes.count == 3, "count params dictates result length")
        precondition(partialOutcomes[0].exitCode == 0, "pkg1 parsed normally")
        precondition(partialOutcomes[1].exitCode == -1, "missing pkg2 marker → sentinel -1")
        precondition(partialOutcomes[1].outputSegment.isEmpty, "missing pkg2 → empty segment")
        precondition(partialOutcomes[2].exitCode == 0, "pkg3 parsed normally despite pkg2 missing")

        // --- count=0：空结果 ---
        let empty = SudoScriptParser.outcomes(in: "whatever", count: 0)
        precondition(empty.isEmpty, "count=0 → empty outcomes")
    }
}
