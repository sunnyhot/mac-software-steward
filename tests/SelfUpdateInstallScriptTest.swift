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
        guard let tempRange = script.range(of: #"TEMP_APP="$DEST_APP.updating.$$""#) else {
            preconditionFailure("Expected script to prepare a temporary destination")
        }
        guard let backupRange = script.range(of: #"BACKUP_APP="$DEST_APP.previous.$$""#) else {
            preconditionFailure("Expected script to prepare a backup destination")
        }
        guard let trapRange = script.range(of: #"trap 'restore_backup' ERR"#) else {
            preconditionFailure("Expected script to restore backup on failure")
        }
        guard let copyRange = script.range(of: #"/usr/bin/ditto "$NEW_APP" "$TEMP_APP""#) else {
            preconditionFailure("Expected script to copy the new app into a temporary destination")
        }
        guard let macOSDirectoryTestRange = script.range(of: #"/bin/test -d "$TEMP_APP/Contents/MacOS""#) else {
            preconditionFailure("Expected script to verify the copied app bundle with macOS /bin/test")
        }
        guard let executableTestRange = script.range(of: #"/bin/test -x "$TEMP_APP/Contents/MacOS/$EXECUTABLE_NAME""#) else {
            preconditionFailure("Expected script to verify the copied app executable with macOS /bin/test")
        }
        guard script.range(of: #"/usr/bin/test"#) == nil else {
            preconditionFailure("macOS does not provide /usr/bin/test; self-update install must use /bin/test")
        }
        guard let backupMoveRange = script.range(of: #"/bin/mv "$DEST_APP" "$BACKUP_APP""#) else {
            preconditionFailure("Expected script to move the old app to backup before replacement")
        }
        guard let replaceRange = script.range(of: #"/bin/mv "$TEMP_APP" "$DEST_APP""#) else {
            preconditionFailure("Expected script to promote temporary app into final destination")
        }
        guard script.range(of: #"/bin/rm -rf "$DEST_APP""#) == nil else {
            preconditionFailure("Script must not delete the destination app before backup")
        }

        precondition(waitRange.lowerBound < termRange.lowerBound, "TERM should happen after graceful wait")
        precondition(termRange.lowerBound < killRange.lowerBound, "KILL should happen after TERM")
        precondition(tempRange.lowerBound < copyRange.lowerBound, "Temp path should be defined before copy")
        precondition(backupRange.lowerBound < backupMoveRange.lowerBound, "Backup path should be defined before backup")
        precondition(trapRange.lowerBound < backupMoveRange.lowerBound, "Rollback trap should be active before moving the old app")
        precondition(copyRange.lowerBound < backupMoveRange.lowerBound, "New app should be copied before old app is moved")
        precondition(copyRange.lowerBound < macOSDirectoryTestRange.lowerBound, "Copied app should be validated after copy")
        precondition(macOSDirectoryTestRange.lowerBound < executableTestRange.lowerBound, "Executable check should happen after bundle directory check")
        precondition(executableTestRange.lowerBound < backupMoveRange.lowerBound, "Copied app should be validated before old app backup")
        precondition(backupMoveRange.lowerBound < replaceRange.lowerBound, "Backup should happen before final replacement")
    }
}
