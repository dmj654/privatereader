import SwiftUI
import ReaderCore

/// 搜索页状态。
///
/// 结果按「书名 + 作者」合并：同一本书在不同源里的条目收进一本书里，
/// 界面上只出现一本书，点进去再选源（换源）。
@MainActor
final class SearchViewModel: ObservableObject {
    enum Kind: String, CaseIterable, Identifiable {
        case novel
        case comic

        var id: String { rawValue }
        var title: String { self == .novel ? "小说" : "漫画" }
    }

    struct MergedBook: Identifiable {
        let id: String
        var name: String
        var author: String
        var coverUrl: String
        var kindText: String
        var lastChapter: String
        var entries: [OnlineBook]
        var sourceNames: [String]
    }

    @Published var query = ""
    @Published var kind: Kind = .novel
    @Published private(set) var books: [MergedBook] = []
    @Published private(set) var history: [String] = []
    @Published private(set) var isSearching = false
    @Published private(set) var totalSources = 0
    @Published private(set) var finishedSources = 0
    @Published private(set) var failedCount = 0
    @Published private(set) var sourceNames: [String: String] = [:]
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    private var coordinator: SearchCoordinator?
    private var searchedKey = ""
    private var failedSources: [LegadoSource] = []
    private static let historyKey = "search.history"

    init() {
        history = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
    }

    var hasResults: Bool { !books.isEmpty }

    func search(env: AppEnvironment, force: Bool = false) {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard force || key != searchedKey || books.isEmpty else { return }

        task?.cancel()
        searchedKey = key
        remember(key)

        isSearching = true
        errorMessage = nil
        books = []
        failedCount = 0
        finishedSources = 0
        failedSources = []

        let wantedComic = kind == .comic

        task = Task { [weak self] in
            guard let self else { return }
            let sources: [LegadoSource]
            do {
                sources = try SourceImportService(repo: env.sources)
                    .enabledSources()
                    .filter { $0.isComic == wantedComic }
            } catch {
                self.isSearching = false
                self.errorMessage = "读取书源失败：\(error.localizedDescription)"
                return
            }

            guard !sources.isEmpty else {
                self.isSearching = false
                self.errorMessage = wantedComic
                    ? "还没有启用的漫画源。去「发现 → 书源」导入漫画源。"
                    : "还没有启用的小说源。去「发现 → 书源」导入书源。"
                return
            }

            self.totalSources = sources.count
            self.finishedSources = 0

            let coordinator = SearchCoordinator(client: env.sourceClient)
            self.coordinator = coordinator

            for await result in await coordinator.search(sources: sources, key: key) {
                if Task.isCancelled { return }
                self.apply(result)
            }

            self.isSearching = false
        }
    }

    func setKind(_ newKind: Kind, env: AppEnvironment) {
        guard newKind != kind else { return }
        kind = newKind
        searchedKey = ""
        books = []
        failedCount = 0
        finishedSources = 0
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            search(env: env, force: true)
        }
    }

    func retryFailed(env: AppEnvironment) {
        guard !failedSources.isEmpty, !searchedKey.isEmpty else { return }
        let retry = failedSources
        failedSources = []
        failedCount = 0
        isSearching = true

        let coordinator = coordinator ?? SearchCoordinator(client: env.sourceClient)
        self.coordinator = coordinator

        Task { [weak self] in
            guard let self else { return }
            for await result in await coordinator.search(sources: retry, key: self.searchedKey) {
                self.apply(result)
            }
            self.isSearching = false
        }
    }

    func selectHistory(_ text: String, env: AppEnvironment) {
        query = text
        searchedKey = ""
        search(env: env, force: true)
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }

    // MARK: 合并

    private func apply(_ result: SourceSearchResult) {
        finishedSources += 1
        sourceNames[result.source.id] = result.source.name

        if let error = result.errorText, !error.isEmpty {
            failedCount += 1
            failedSources.append(result.source)
            return
        }

        for online in result.books {
            merge(online, sourceName: result.source.name)
        }
        books.sort { lhs, rhs in
            if lhs.entries.count != rhs.entries.count {
                return lhs.entries.count > rhs.entries.count
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func merge(_ online: OnlineBook, sourceName: String) {
        let key = identity(of: online)
        if let index = books.firstIndex(where: { $0.id == key }) {
            if !books[index].entries.contains(where: { $0.sourceId == online.sourceId }) {
                books[index].entries.append(online)
                books[index].sourceNames.append(sourceName)
            }
            if books[index].coverUrl.isEmpty { books[index].coverUrl = online.coverUrl }
            if !online.lastChapter.isEmpty { books[index].lastChapter = online.lastChapter }
        } else {
            books.append(MergedBook(
                id: key,
                name: online.name,
                author: online.author,
                coverUrl: online.coverUrl,
                kindText: online.kind,
                lastChapter: online.lastChapter,
                entries: [online],
                sourceNames: [sourceName]
            ))
        }
    }

    private func identity(of book: OnlineBook) -> String {
        let name = book.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let author = book.author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return author.isEmpty ? name : name + "|" + author
    }

    private func remember(_ key: String) {
        var list = history.filter { $0 != key }
        list.insert(key, at: 0)
        history = Array(list.prefix(12))
        UserDefaults.standard.set(history, forKey: Self.historyKey)
    }
}
