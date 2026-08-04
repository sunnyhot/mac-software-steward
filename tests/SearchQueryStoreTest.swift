import Foundation

@main
struct SearchQueryStoreTest {
    @MainActor
    static func main() async {
        let store = SearchQueryStore(debounceMilliseconds: 20)

        store.updateDraft("no")
        store.updateDraft("node")
        precondition(store.query.isEmpty, "搜索条件不应在每次按键时立即发布")

        try? await Task.sleep(nanoseconds: 60_000_000)
        precondition(store.query == "node", "应只发布最后一次延迟输入")

        store.updateDraft("brew")
        store.flush()
        precondition(store.query == "brew", "提交搜索时应立即发布")

        store.clear()
        precondition(store.query.isEmpty && store.draft.isEmpty, "清除应同步重置输入与筛选")
    }
}
