import Foundation

@main
struct SudoScriptBuilderTest {
    static func main() {
        let brewPath = "/opt/homebrew/bin/brew"

        // --- N=3：分隔符、标记、路径、顺序 ---
        let script3 = SudoScriptBuilder.script(
            brewPath: brewPath,
            packageNames: ["pkgA", "pkgB", "pkgC"],
            pathEnv: "/opt/homebrew/bin:/usr/local/bin",
            homeEnv: "/Users/test"
        )
        precondition(script3.contains("with administrator privileges"), "must request admin privileges")
        precondition(script3.contains("\(brewPath) upgrade --cask pkgA"), "must include pkgA with absolute brew path")
        precondition(script3.contains("\(brewPath) upgrade --cask pkgB"), "must include pkgB")
        precondition(script3.contains("\(brewPath) upgrade --cask pkgC"), "must include pkgC")
        precondition(script3.contains("echo \"__RC_1_$?__\""), "pkgA must carry __RC_1_ marker")
        precondition(script3.contains("echo \"__RC_2_$?__\""), "pkgB must carry __RC_2_ marker")
        precondition(script3.contains("echo \"__RC_3_$?__\""), "pkgC must carry __RC_3_ marker")
        precondition(script3.contains("; echo"), "statements must be ;-separated per cask (failure isolation)")
        precondition(script3.contains("export PATH=/opt/homebrew/bin:/usr/local/bin"), "must export PATH for root shell")
        precondition(script3.contains("export HOME=/Users/test"), "must export HOME for root shell")

        // 顺序：pkgA 标记必须出现在 pkgB 标记之前
        if let aRange = script3.range(of: "__RC_1_"), let bRange = script3.range(of: "__RC_2_") {
            precondition(aRange.lowerBound < bRange.lowerBound, "markers must preserve package order")
        } else {
            preconditionFailure("markers not found for ordering check")
        }

        // --- N=1：单包也要正确 ---
        let script1 = SudoScriptBuilder.script(brewPath: brewPath, packageNames: ["only"], pathEnv: "/x", homeEnv: "/h")
        precondition(script1.contains("\(brewPath) upgrade --cask only"), "single package must appear")
        precondition(script1.contains("__RC_1_$?__"), "single package must carry __RC_1_ marker")

        // --- osaArguments：必须是 ["-e", script] ---
        let args = SudoScriptBuilder.osaArguments(script1)
        precondition(args == ["-e", script1], "osaArguments must wrap script as -e arg, got \(args)")

        // --- N=0：空输入返回空 body（调用方应避免，但函数不得崩溃） ---
        let script0 = SudoScriptBuilder.script(brewPath: brewPath, packageNames: [], pathEnv: "/x", homeEnv: "/h")
        precondition(script0.contains("with administrator privileges"), "even empty batch keeps admin privileges wrapper")
        precondition(!script0.contains("__RC_"), "empty batch must emit no markers")
    }
}
