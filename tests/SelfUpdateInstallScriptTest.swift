import Foundation

@main
struct SelfUpdateInstallScriptTest {
    static func main() {
        let script = SelfUpdateInstallScript.content
        guard let waitRange = script.range(of: "for i in {1..80}") else {
            preconditionFailure("Expected script to wait for the app to quit")
        }
        guard let termRange = script.range(of: #"/bin/kill -TERM "$APP_PID""#) else {
            preconditionFailure("Expected script to terminate the old app if it is still running")
        }
        guard let killRange = script.range(of: #"/bin/kill -KILL "$APP_PID""#) else {
            preconditionFailure("Expected script to force kill the old app if TERM does not work")
        }
        guard let replaceRange = script.range(of: #"/bin/rm -rf "$DEST_APP""#) else {
            preconditionFailure("Expected script to replace the destination app")
        }

        precondition(waitRange.lowerBound < termRange.lowerBound, "TERM should happen after the graceful wait")
        precondition(termRange.lowerBound < killRange.lowerBound, "KILL should happen after TERM")
        precondition(killRange.lowerBound < replaceRange.lowerBound, "Replacement should happen only after the old app is gone")
    }
}
