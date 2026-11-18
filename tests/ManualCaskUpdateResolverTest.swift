import Foundation

@main
struct ManualCaskUpdateResolverTest {
    static func main() {
        precondition(ManualCaskUpdateResolver.versionsMatch("4.3.0-beta", "4.3.0-beta"))
        precondition(ManualCaskUpdateResolver.versionsMatch("v4.3.0-beta-20260820.1", "4.3.0-beta"))
        precondition(ManualCaskUpdateResolver.versionsMatch("4.3.0-beta", "4.3.0-beta-20260820.1"))
        precondition(ManualCaskUpdateResolver.versionsMatch("4.3.0-beta-1", "4.3.0-beta"))
        precondition(!ManualCaskUpdateResolver.versionsMatch("4.3.0-beta.1", "4.3.0-beta"))
        precondition(!ManualCaskUpdateResolver.versionsMatch("4.3.0-beta-20260820.1", "4.3.0"))
        precondition(!ManualCaskUpdateResolver.versionsMatch("4.3.0-beta-20260820.1", "4.3.0-alpha"))
        precondition(!ManualCaskUpdateResolver.versionsMatch("4.3.0-beta-1junk", "4.3.0-beta"))

        let json = #"{"casks":[{"token":"mos","version":"4.2.1"},{"full_token":"homebrew/cask/mos@beta","version":"4.3.0-beta-20260820.1"}]}"#
        precondition(ManualCaskUpdateResolver.caskVersion(fromBrewInfoJSON: json, token: "mos") == "4.2.1")
        precondition(ManualCaskUpdateResolver.caskVersion(fromBrewInfoJSON: json, token: "mos@beta") == "4.3.0-beta-20260820.1")
        precondition(ManualCaskUpdateResolver.caskVersion(fromBrewInfoJSON: json, token: "homebrew/cask/mos@beta") == "4.3.0-beta-20260820.1")
        precondition(ManualCaskUpdateResolver.caskVersion(fromBrewInfoJSON: "not-json", token: "mos") == nil)
    }
}
