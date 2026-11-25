import SwiftUI
import ReaderCore

/// 搜索页的状态与流程。放成 ObservableObject 是因为「逐组填充」要频繁局部刷新，
/// 全塞进 View 的 @State 会让 body 变得难读。
@MainActor
final class SearchViewModel: ObservableObject {
    struct Group: Identifiable {
        let id: String
        let source: LegadoSource
        var books: [OnlineBook] = []
        var error: String?
        var elapsed: Double = 0
        var isLoading = true
    }

    @Published var query = ""
    @Published private(set) var groups: [Group] = []
    @Published private(set) var localMatches: [Book] = []
    @Published private(set) var isSearching = false
    @Published private(set) var history: [String] = []
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    private var coordinator: SearchCoordinator?
    private var searchedKey = ""
    private static let historyKey = "search.history"

    init() {
        history = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
    }

    var hasResults: Bool {
        !localMatches.isEmpty || groups.contains { !$0.books.isEmpty }
    }

    var finishedCount: Int { groups.filter { !$0.isLoading }.count }

    func search(env: AppEnvironment) {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard key != searchedKey || groups.isEmpty else { return }

        task?.cancel()
        searchedKey = key
        remember(key)

        localMatches = (try? env.books.all().filter { book in
            book.title.localizedCaseInsensitiveContains(key)
                || (book.author?.localizedCaseInsensitiveContains(key) ?? false)
        }) ?? []

        isSearching = true
        errorMessage = nil
        groups = []

        task = Task { [weak self] in
            guard let self else { return }
            let sources: [LegadoSource]
            do {
                sources = try SourceImportService(repo: env.sources).enabledSources()
            } catch {
                self.isSearching = false
                self.errorMessage = "读取书源失败：\(error.localizedDescription)"
                return
            }

            guard !sources.isEmpty else {
                self.isSearching = false
                self.errorMessage = "还没有启用的书源。去「发现 → 书源」导入一份。"
                return
            }

            self.groups = sources.map { Group(id: $0.id, source: $0) }

            let coordinator = SearchCoordinator(client: env.sourceClient)
            self.coordinator = coordinator

            for await result in await coordinator.search(sources: sources, key: key) {
                if Task.isCancelled { return }
                self.apply(result)
            }
            self.isSearching = false
        }
    }

    func retry(_ group: Group, env: AppEnvironment) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].isLoading = true
        groups[index].error = nil

        let coordinator = coordinator ?? SearchCoordinator(client: env.sourceClient)
        self.coordinator = coordinator

        Task { [weak self] in
            guard let self else { return }
            for await result in await coordinator.search(sources: [group.source], key: self.searchedKey) {
                self.apply(result)
            }
        }
    }

    func selectHistory(_ text: String, env: AppEnvironment) {
        query = text
        searchedKey = ""
        search(env: env)
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }

    private func apply(_ result: SourceSearchResult) {
        guard let index = groups.firstIndex(where: { $0.id == result.source.id }) else { return }
        groups[index].books = result.books
        groups[index].error = result.errorText
        groups[index].elapsed = result.elapsed
        groups[index].isLoading = false
    }

    private func remember(_ key: String) {
        var list = history.filter { $0 != key }
        list.insert(key, at: 0)
        history = Array(list.prefix(12))
        UserDefaults.standard.set(history, forKey: Self.historyKey)
    }
}
