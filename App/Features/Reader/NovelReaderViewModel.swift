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

    private let initialChapter: Int?

    init(book: Book,
         provider: ChapterProvider,
         progressRepo: ProgressRepository,
         bookmarkRepo: BookmarkRepository,
         booksRepo: BookRepository,
         initialChapter: Int? = nil) {
        self.book = book
        self.initialChapter = initialChapter
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
            if let initialChapter {
                chapterIndex = min(max(initialChapter, 0), max(chapters.count - 1, 0))
            } else if let saved = try progressRepo.fetch(bookId: book.id) {
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

    /// 章标题作为正文的第一段参与排版，而不是浮在正文上方的装饰。
    /// 这样翻到本章第一页时标题自然出现在页首，分页也算得准，不会盖住文字。
    private func attributedBody(for chapter: NovelChapter) -> NSAttributedString {
        let color = UIColor(theme.textColor)
        let result = NSMutableAttributedString()

        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.alignment = .center
        titleParagraph.lineHeightMultiple = 1.45
        titleParagraph.paragraphSpacing = 22
        titleParagraph.paragraphSpacingBefore = 8

        let titleFont = UIFont.systemFont(ofSize: style.fontSize * 1.45, weight: .semibold)
        result.append(NSAttributedString(
            string: chapter.title + "\n",
            attributes: [
                .font: titleFont,
                .foregroundColor: color,
                .paragraphStyle: titleParagraph
            ]
        ))

        let body = ReaderStyle.normalizedBody(chapter.body.isEmpty ? "" : chapter.body)
        if !body.isEmpty {
            result.append(NSAttributedString(
                string: body,
                attributes: style.attributes(color: color.cgColor)
            ))
        }
        return result
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

    /// 取相邻页的富文本，给翻页动画用：新页要提前画出来，才能和旧页同时在场。
    /// 只在本章内可用；跨章返回 nil，调用方退化成淡入淡出。
    func pageText(offset: Int) -> NSAttributedString? {
        guard let chapter = currentChapter else { return nil }
        let target = pageIndex + offset
        guard pageRanges.indices.contains(target) else { return nil }

        let attributed = attributedBody(for: chapter)
        let range = pageRanges[target]
        guard range.location + range.length <= attributed.length else { return nil }
        return attributed.attributedSubstring(from: range)
    }

    /// 还能不能往这个方向翻。翻不动时不要再播动画，否则会出现"滑走又滑回原样"的怪现象。
    func canTurn(by delta: Int) -> Bool {
        guard !chapters.isEmpty else { return false }
        if delta < 0 {
            return pageIndex > 0 || chapterIndex > 0
        }
        return pageIndex < max(pageRanges.count - 1, 0) || chapterIndex < chapters.count - 1
    }

    /// 按全书百分比跳章。滑杆松手时调用。
    func seek(toPercent percent: Double) {
        guard !chapters.isEmpty else { return }
        jump(toChapter: ProgressMath.chapterIndex(fromPercent: percent, chapterCount: chapters.count))
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
