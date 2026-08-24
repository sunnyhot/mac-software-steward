import Foundation

@main
struct SearchQueryStoreTest {
    @MainActor
    static func main() async {
        let store = SearchQueryStore(debounceMilliseconds: 20)

        store.updateDraft("no")
        store.updateDraft("node")
        precondition(store.query.isEmpty, "搜索条件不应在每次按键时立即发布")

        // CI 慢机的任务调度延迟远超防抖窗口，单次固定 sleep 容易在防抖尚未触发时断言失败，
        // 改为轮询等待，留出足够的调度余量。
        var published = false
        for _ in 0 ..< 100 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if store.query == "node" {
                published = true
                break
            }
        }
        precondition(published, "应只发布最后一次延迟输入")

        store.updateDraft("brew")
        store.flush()
        precondition(store.query == "brew", "提交搜索时应立即发布")

        store.clear()
        precondition(store.query.isEmpty && store.draft.isEmpty, "清除应同步重置输入与筛选")
    }
}
