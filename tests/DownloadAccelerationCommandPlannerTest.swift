import Foundation

@main
struct DownloadAccelerationCommandPlannerTest {
    static func main() {
        let strategies = [
            DownloadAccelerationStrategy(kind: .inheritedProxy, proxyURLString: "http://127.0.0.1:7890"),
            DownloadAccelerationStrategy(kind: .systemProxy, proxyURLString: "http://127.0.0.1:8080"),
            DownloadAccelerationStrategy(kind: .direct, proxyURLString: nil)
        ]
        let first = CommandAccelerationAttempt(strategies: strategies, attemptIndex: 0, maxAttempts: 3)
        precondition(first.currentStrategy.title == "环境代理")
        precondition(first.attemptText == "第 1/3 次")
        precondition(first.next()?.currentStrategy.title == "系统代理")
        precondition(first.next()?.next()?.currentStrategy.title == "直连")
        precondition(first.next()?.next()?.next() == nil)
    }
}
