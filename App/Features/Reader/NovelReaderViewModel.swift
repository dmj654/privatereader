import SwiftUI
import UIKit
import ReaderCore

@MainActor
final class NovelReaderViewModel: ObservableObject {
    let book: Book

    private let provider: ChapterProvider
    private let progressRepo: ProgressRepository
    private let bookmarkRepo: BookmarkRepository
    private let booksRepo: BookRepository

    @Published private(set) var chapters: [NovelChapter] = []
    @Published var chapterIndex: Int = 0
    @Published var pageIndex: Int = 0
    @Published private(set) var pageRanges: [NSRange] = []
    @Published var style: ReaderStyle = .default
    @Published var theme: ReaderTheme = .day
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var bookmarks: [Bookmark] = []
    @Published var isMenuVisible = false
    @Published var isDarkChrome = false

    private var lastPageSize: CGSize = .zero
    private var lastSavedAt: TimeInterval = 0
    private var sessionStartedAt: Date?

    init(book: Book,
         provider: ChapterProvider,
         progressRepo: ProgressRepository,
         bookmarkRepo: BookmarkRepository,
         booksRepo: BookRepository) {
        self.book = book
        self.provider = provider
        self.progressRepo = progressRepo
        self.bookmarkRepo = bookmarkRepo
        self.booksRepo = booksRepo
    }

    var currentChapter: NovelChapter? {
        guard chapters.indices.contains(chapterIndex) else { return nil }
        return chapters[chapterIndex]
    }

    var chapterTitle: String {
        currentChapter?.title ?? book.title
    }

    var pageCount: Int { max(pageRanges.count, 1) }
    var displayPage: Int { min(pageIndex + 1, pageCount) }

    var progressPercent: Double {
        let within = pageCount > 1 ? Double(pageIndex) / Double(pageCount - 1) : 0
        return ProgressMath.percent(chapterIndex: chapterIndex, chapterCount: chapters.count, chapterProgress: within)
    }

    // MARK: 加载

    func load() {
        isLoading = true
        do {
            chapters = try provider.chapters(for: book)
            if let saved = try progressRepo.fetch(bookId: book.id) {
                chapterIndex = min(max(saved.chapterIndex, 0), max(chapters.count - 1, 0))
            }
            bookmarks = (try? bookmarkRepo.list(bookId: book.id)) ?? []
            sessionStartedAt = Date()
            errorMessage = nil
        } catch {
            chapters = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    // MARK: 分页

    func repaginateIfNeeded(size: CGSize) {
        guard size.width > 40, size.height > 40 else { return }
        guard size != lastPageSize || pageRanges.isEmpty else { return }
        lastPageSize = size
        repaginate()
    }

    func repaginate() {
        guard let chapter = currentChapter, lastPageSize.width > 40 else { return }
        let attributed = attributedBody(for: chapter)
        pageRanges = Paginator.pageRanges(attributedString: attributed, pageSize: lastPageSize)
        pageIndex = min(pageIndex, max(pageRanges.count - 1, 0))
    }

    private func attributedBody(for chapter: NovelChapter) -> NSAttributedString {
        let body = ReaderStyle.normalizedBody(chapter.body.isEmpty ? chapter.title : chapter.body)
        return NSAttributedString(string: body, attributes: style.attributes(color: UIColor(theme.textColor).cgColor))
    }

    var currentPageText: NSAttributedString {
        guard let chapter = currentChapter,
              pageRanges.indices.contains(pageIndex) else {
            return NSAttributedString(string: "")
        }
        let attributed = attributedBody(for: chapter)
        let range = pageRanges[pageIndex]
        guard range.location + range.length <= attributed.length else { return attributed }
        return attributed.attributedSubstring(from: range)
    }

    // MARK: 翻页

    func turnPage(by delta: Int) {
        guard !chapters.isEmpty else { return }
        let target = pageIndex + delta
        if target < 0 {
            if chapterIndex > 0 {
                chapterIndex -= 1
                repaginate()
                pageIndex = max(pageRanges.count - 1, 0)
                persistProgress()
            }
            return
        }
        if target >= pageRanges.count {
            if chapterIndex < chapters.count - 1 {
                chapterIndex += 1
                repaginate()
                pageIndex = 0
                persistProgress()
            }
            return
        }
        pageIndex = target
        persistProgress()
    }

    func jump(toChapter index: Int) {
        guard chapters.indices.contains(index) else { return }
        chapterIndex = index
        repaginate()
        pageIndex = 0
        persistProgress()
    }

    // MARK: 持久化

    func persistProgress(force: Bool = false) {
        let now = Date().timeIntervalSince1970
        guard force || now - lastSavedAt > 1 else { return }
        lastSavedAt = now

        let within = pageCount > 1 ? Double(pageIndex) / Double(pageCount - 1) : 0
        let percent = ProgressMath.percent(chapterIndex: chapterIndex, chapterCount: chapters.count, chapterProgress: within)
        let record = ReadingProgress(
            bookId: book.id,
            chapterIndex: chapterIndex,
            offset: pageIndex,
            percent: percent,
            updatedAt: Int(now)
        )
        try? progressRepo.save(record)
        try? booksRepo.touch(bookId: book.id, at: Int(now))
    }

    func finishSession() {
        persistProgress(force: true)
        guard let started = sessionStartedAt else { return }
        let seconds = Int(Date().timeIntervalSince(started))
        sessionStartedAt = nil
        guard seconds > 5 else { return }
        // 会话记录由 AppEnvironment 在关闭阅读器时写入，这里只负责提供时长
        pendingSessionDuration = seconds
    }

    private(set) var pendingSessionDuration: Int?

    // MARK: 书签

    func addBookmark() {
        let excerpt = currentPageText.string
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = String(excerpt.prefix(30))
        let bookmark = Bookmark(bookId: book.id, chapterIndex: chapterIndex, offset: pageIndex, excerpt: trimmed)
        try? bookmarkRepo.add(bookmark)
        bookmarks = (try? bookmarkRepo.list(bookId: book.id)) ?? []
    }

    func removeBookmark(_ bookmark: Bookmark) {
        try? bookmarkRepo.delete(id: bookmark.id)
        bookmarks = (try? bookmarkRepo.list(bookId: book.id)) ?? []
    }
}
