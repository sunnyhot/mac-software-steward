import Foundation

@main
struct AppUpdateDialogLayoutTest {
    static func main() {
        precondition(AppUpdateDialogLayout.dialogWidth <= 700, "Update dialog should stay compact")
        precondition(AppUpdateDialogLayout.dialogHeight <= 560, "Update dialog should not dominate the app window")
        precondition(AppUpdateDialogLayout.iconSize <= 64, "Update icon should not overpower the title")
        precondition(AppUpdateDialogLayout.releaseNotesMaxHeight <= 220, "Release notes should scroll inside a compact area")
    }
}
