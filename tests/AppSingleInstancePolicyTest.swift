import Foundation

@main
struct AppSingleInstancePolicyTest {
    static func main() {
        precondition(
            !AppSingleInstancePolicy.shouldTerminateCurrent(
                currentProcessIdentifier: 200,
                runningProcessIdentifiers: [200]
            ),
            "A single running instance must be allowed"
        )
        precondition(
            AppSingleInstancePolicy.shouldTerminateCurrent(
                currentProcessIdentifier: 200,
                runningProcessIdentifiers: [100, 200]
            ),
            "A newer duplicate instance should terminate itself"
        )
        precondition(
            !AppSingleInstancePolicy.shouldTerminateCurrent(
                currentProcessIdentifier: 100,
                runningProcessIdentifiers: [100, 200]
            ),
            "The oldest instance should stay alive"
        )
    }
}
