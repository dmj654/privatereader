import SwiftUI
import ReaderCore

/// 合并结果的详情页。
///
/// 搜索页点一本书直接到这里：先自动挑一个能取到目录的源（优先章节多的），
/// 想换源再点「换源」，而不是先把一堆源摊在用户面前。
struct MergedOnlineDetailView: View {
    let book: SearchViewModel.MergedBook

    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var model: MergedDetailModel
    @State private var showSourcePicker = false
    @State private var showReader = false

    init(book: SearchViewModel.MergedBook) {
        self.book = book
        _model = StateObject(wrappedValue: MergedDetailModel(book: book))
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            if model.isLoading {
                VStack(spacing: 10) {
                    ProgressView().tint(Palette.accent)
                    Text("正在确认可用的源…")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.ink3)
                }
            } else if let error = model.errorMessage {
                VStack(spacing: 10) {
                    EmptyStateView(symbol: "exclamationmark.triangle", title: "打不开这本书", message: error)
                    Button("重试") {
                        Task { await model.load(env: env) }
                    }
                    .buttonStyle(SecondaryButtonStyle(height: 40))
                    .frame(width: 140)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        hero
                        sourceLine
                        actionArea
                        if !model.intro.isEmpty { introCard }
                        if !model.chapters.isEmpty { tocCard }
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(env: env) }
        .sheet(isPresented: $showSourcePicker) {
            sourcePicker
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showReader) {
            if let shelfBook = model.shelfBook {
                if shelfBook.type == .comic {
                    OnlineComicView(book: shelfBook)
                        .environmentObject(env)
                } else {
                    NovelReaderView(book: shelfBook, env: env)
                        .environmentObject(env)
                }
            }
        }
    }

    // MARK: 头部

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            OnlineCoverView(url: model.coverUrl, title: book.name)
                .frame(width: 92, height: 126)

            VStack(alignment: .leading, spacing: 5) {
                Text(model.name.isEmpty ? book.name : model.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)

                Text([model.author, book.kindText]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)

                if !model.lastChapter.isEmpty {
                    Text("最新：\(model.lastChapter)")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if !model.chapters.isEmpty {
                        tag("\(model.chapters.count) \(book.isComic ? "话" : "章")")
                    }
                    tag("\(book.entries.count) 个源")
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            }
    }

    // MARK: 来源

    private var sourceLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 11))
                .foregroundStyle(Palette.accent)

            Text("当前源：\(model.sourceName)")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)

            Spacer(minLength: 0)

            if model.shelfBook == nil {
                Button {
                    showSourcePicker = true
                } label: {
                    Text("换源")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Palette.accentSoft)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text("已加入书架")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink3)
            }
        }
        .padding(11)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
    }

    // MARK: 操作

    private var actionArea: some View {
        HStack(spacing: 10) {
            Button {
                startReading()
            } label: {
                if model.isAdding {
                    ProgressView().tint(.white)
                } else {
                    Text(model.shelfBook == nil ? "加入书架并阅读" : "开始阅读")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isAdding || model.chapters.isEmpty)

            if model.shelfBook == nil {
                Button {
                    addOnly()
                } label: {
                    Text("加入书架")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 96, height: 46)
                        .background(Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                .strokeBorder(Palette.lineStrong, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(model.isAdding)
            }
        }
    }

    private var introCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 7) {
                Text("简介")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                Text(model.intro)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.ink2)
                    .lineSpacing(4)
                    .lineLimit(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tocCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("目录")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.ink2)
                    Spacer()
                    Text("共 \(model.chapters.count) \(book.isComic ? "话" : "章")")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.ink3)
                }

                ForEach(Array(model.chapters.prefix(8).enumerated()), id: \.offset) { index, chapter in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(Palette.ink3)
                            .frame(width: 22, alignment: .trailing)
                        Text(chapter.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }

                if model.chapters.count > 8 {
                    Text("还有 \(model.chapters.count - 8) \(book.isComic ? "话" : "章")")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 换源

    private var sourcePicker: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(book.entries.enumerated()), id: \.offset) { index, entry in
                        Button {
                            showSourcePicker = false
                            Task { await model.pick(sourceId: entry.sourceId, env: env) }
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sourceName(index))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    Text(entry.lastChapter.isEmpty ? "最新章节未知" : entry.lastChapter)
                                        .font(Typo.micro)
                                        .foregroundStyle(Palette.ink3)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if entry.sourceId == model.chosen?.sourceId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Palette.accent)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("换源会重新取目录；选到取不到目录的源会提示你换回来。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("换源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showSourcePicker = false }
                }
            }
        }
    }

    private func sourceName(_ index: Int) -> String {
        guard book.sourceNames.indices.contains(index) else { return "书源 \(index + 1)" }
        return book.sourceNames[index]
    }

    // MARK: 动作

    private func startReading() {
        Task {
            if let book = await model.ensureShelf(env: env) {
                model.shelfBook = book
                showReader = true
            }
        }
    }

    private func addOnly() {
        Task {
            _ = await model.ensureShelf(env: env)
        }
    }
}

// MARK: - 详情模型

@MainActor
final class MergedDetailModel: ObservableObject {
    let book: SearchViewModel.MergedBook

    @Published var chosen: OnlineBook?
    @Published var sourceName = ""
    @Published var chapters: [OnlineChapter] = []
    @Published var intro = ""
    @Published var coverUrl = ""
    @Published var name = ""
    @Published var author = ""
    @Published var lastChapter = ""
    @Published var isLoading = true
    @Published var isAdding = false
    @Published var errorMessage: String?
    @Published var shelfBook: Book?

    private var source: LegadoSource?

    init(book: SearchViewModel.MergedBook) {
        self.book = book
        self.name = book.name
        self.author = book.author
        self.coverUrl = book.coverUrl
        self.lastChapter = book.lastChapter
    }

    func load(env: AppEnvironment, preferred: String? = nil) async {
        // 从阅读器返回 / 视图重建时不要重新探测一遍，用户看到的还是同一个源。
        if preferred == nil, chosen != nil {
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        chapters = []
        chosen = nil

        let ordered = orderedEntries(preferred: preferred)
        var best: (OnlineBook, LegadoSource, [OnlineChapter])?
        var readableBest: (OnlineBook, LegadoSource, [OnlineChapter])?
        var tried = 0

        for entry in ordered.prefix(4) {
            guard let source = resolve(entry.sourceId, env: env) else { continue }
            tried += 1
            guard let toc = try? await env.sourceClient.chapters(source: source, book: entry),
                  !toc.isEmpty else { continue }

            if best == nil || toc.count > best!.2.count {
                best = (entry, source, toc)
            }

            // 目录能取到不代表正文能看。再探一章，确认这个源真的能读。
            if await canRead(entry: entry, source: source, chapter: toc[0], env: env) {
                if readableBest == nil || toc.count > readableBest!.2.count {
                    readableBest = (entry, source, toc)
                }
                if toc.count >= 120 { break }
            }
        }

        if let chosen = readableBest ?? best {
            apply(chosen.0, source: chosen.1, chapters: chosen.2)
            isLoading = false
        } else {
            isLoading = false
            errorMessage = tried == 0
                ? "这些源都已被删除或关闭，换一本书试试。"
                : "这几个源都没取到目录。可以稍后重试，或换一个关键词。"
        }
    }

    func pick(sourceId: String, env: AppEnvironment) async {
        await load(env: env, preferred: sourceId)
    }

    /// 加入书架（已加过就复用那本）。返回可用于打开阅读器的 Book。
    func ensureShelf(env: AppEnvironment) async -> Book? {
        if let shelfBook { return shelfBook }
        guard let chosen, let source else {
            errorMessage = "还没有选中可用的源。"
            return nil
        }

        isAdding = true
        defer { isAdding = false }

        if let existing = findExisting(chosen, env: env) {
            shelfBook = existing
            return existing
        }

        do {
            let service = OnlineBookService(
                client: env.sourceClient,
                library: OnlineLibrary(paths: env.paths)
            )
            let bundle = try await service.prepare(chosen, source: source)
            try env.books.insert(bundle.book)
            shelfBook = bundle.book
            return bundle.book
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    // MARK: 内部

    /// 取第一章确认正文 / 图片真的能拿到。只看目录，很多死源也能骗过。
    private func canRead(entry: OnlineBook,
                         source: LegadoSource,
                         chapter: OnlineChapter,
                         env: AppEnvironment) async -> Bool {
        if source.isComic {
            let pages = try? await env.sourceClient.comicPages(source: source, chapter: chapter)
            return !(pages?.isEmpty ?? true)
        }
        let text = try? await env.sourceClient.content(source: source, chapter: chapter)
        return !(text?.isEmpty ?? true)
    }

    private func apply(_ entry: OnlineBook, source: LegadoSource, chapters: [OnlineChapter]) {
        chosen = entry
        self.source = source
        sourceName = source.name
        self.chapters = chapters
        name = entry.name.isEmpty ? book.name : entry.name
        author = entry.author.isEmpty ? book.author : entry.author
        coverUrl = entry.coverUrl.isEmpty ? book.coverUrl : entry.coverUrl
        lastChapter = entry.lastChapter.isEmpty ? book.lastChapter : entry.lastChapter

        intro = entry.intro
        if intro.isEmpty {
            intro = book.entries.first(where: { !$0.intro.isEmpty })?.intro ?? ""
        }
    }

    private func orderedEntries(preferred: String?) -> [OnlineBook] {
        var list = book.entries
        if let preferred,
           let index = list.firstIndex(where: { $0.sourceId == preferred }) {
            let entry = list.remove(at: index)
            list.insert(entry, at: 0)
            return list
        }

        // 规则越完整越可能取到完整目录；有最新章节的排前面
        return list.sorted { lhs, rhs in
            score(lhs) > score(rhs)
        }
    }

    private func score(_ entry: OnlineBook) -> Int {
        var value = 0
        if !entry.lastChapter.isEmpty { value += 2 }
        if !entry.intro.isEmpty { value += 1 }
        if !entry.coverUrl.isEmpty { value += 1 }
        return value
    }

    private func resolve(_ id: String, env: AppEnvironment) -> LegadoSource? {
        guard let record = try? env.sources.fetch(id: id) else { return nil }
        return SourceImportService(repo: env.sources).executable(from: record)
    }

    private func findExisting(_ entry: OnlineBook, env: AppEnvironment) -> Book? {
        guard let all = try? env.books.all() else { return nil }
        return all.first {
            $0.origin == .remote
                && $0.sourceId == entry.sourceId
                && $0.sourceUrl == entry.bookUrl
        }
    }
}
