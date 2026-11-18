import Foundation

@main
struct CaskReceiptVerificationTest {
    static func main() {
        let removedOutputs = [
            "Error: No such cask 'bartender'.",
            "Error: Cask 'bartender' is not installed.",
            "Error: No cask found for bartender."
        ]
        for output in removedOutputs {
            let result = CommandResult(ok: false, code: 1, stdout: "", stderr: output)
            precondition(CaskReceiptVerification.isRemoved(result), output)
        }

        let present = CommandResult(ok: true, code: 0, stdout: "/opt/homebrew/Caskroom/bartender", stderr: "")
        precondition(!CaskReceiptVerification.isRemoved(present))
        let timeout = CommandResult(ok: false, code: -1, stdout: "", stderr: "")
        precondition(!CaskReceiptVerification.isRemoved(timeout))
        let sudo = CommandResult(ok: false, code: 1, stdout: "", stderr: "sudo: a password is required")
        precondition(!CaskReceiptVerification.isRemoved(sudo))
        let unrelated = CommandResult(ok: false, code: 1, stdout: "", stderr: "network unavailable")
        precondition(!CaskReceiptVerification.isRemoved(unrelated))
    }
}
