import Combine
import Foundation

/// 独立于维护业务状态的搜索输入。
///
/// 输入框自行维护即时文本，列表只观察延迟发布的 `query`。这样快速输入时不会让
/// `StewardModel` 及整棵维护界面在每个按键上重绘。
@MainActor
final class SearchQueryStore: ObservableObject {
    @Published private(set) var query = ""
    private(set) var draft = ""

    private let debounceNanoseconds: UInt64
    private var debounceTask: Task<Void, Never>?

    init(debounceMilliseconds: UInt64 = 220) {
        debounceNanoseconds = debounceMilliseconds * 1_000_000
    }

    func updateDraft(_ value: String) {
        draft = value
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            publishDraft()
        }
    }

    func clear() {
        debounceTask?.cancel()
        draft = ""
        publishDraft()
    }

    func flush() {
        debounceTask?.cancel()
        publishDraft()
    }

    private func publishDraft() {
        guard query != draft else { return }
        query = draft
    }
}
