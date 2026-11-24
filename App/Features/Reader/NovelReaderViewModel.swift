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
    private let positionStore: ReadingPositionStore
    private let log: ImportLog?
    private var pendingPage: Int?
    private var lastLoggedChapter = -1

    // 章节富文本缓存：正文与分页、朗读必须共用同一份字符串，偏移才对得上
    private var cachedAttributed: NSAttributedString?
    private var cachedKey: CacheKey?
    private struct CacheKey: Equatable {
        let chapter: Int
        let style: ReaderStyle
        let theme: String
    }

    // 朗读
    @Published private(set) var speechIndex: Int?
    private var speechQueue: SpeechQueue?
    private var speechSentences: [SpeechSentence] = []
    private var speechSentenceKey: CacheKey?

    @Published private(set) var chapters: [NovelChapter] = []
    @Published var chapterIndex: Int = 0
    @Published var pageIndex: Int = 0
    @Published private(set) var pageRanges: [NSRange] = []

    /// 排版与主题：改了立刻写回偏好，下次打开还是这一套。
    @Published var style: ReaderStyle = .default {
        didSet { preferences?.style = style }
    }
    @Published var theme: ReaderTheme = .day {
        didSet { preferences?.theme = theme }
    }

    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var bookmarks: [Bookmark] = []
    @Published var isMenuVisible = false
    @Published var isDarkChrome = false

    /// 偏好只在阅读器活着时有意义，用 weak 防止它反向延长偏好对象的生命周期。
    private weak var preferences: ReaderPreferences?

    private var lastPageSize: CGSize = .zero
    private var lastSavedAt: TimeInterval = 0
    private var sessionStartedAt: Date?

    private let initialChapter: Int?

    init(book: Book,
         provider: ChapterProvider,
         progressRepo: ProgressRepository,
         bookmarkRepo: BookmarkRepository,
         booksRepo: BookRepository,
         initialChapter: Int? = nil,
         log: ImportLog? = nil) {
        self.book = book
        self.initialChapter = initialChapter
        self.provider = provider
        self.progressRepo = progressRepo
        self.bookmarkRepo = bookmarkRepo
        self.booksRepo = booksRepo
        self.positionStore = ReadingPositionStore(repo: progressRepo)
        self.log = log
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

    /// 接上偏好：把上次的字号、行距、主题拿进来，并让之后的修改自动写回。
    /// 必须在 `load()` 之前调用——分页要用正确的排版参数，否则第一屏会按默认字号排一次再重排。
    func attach(preferences: ReaderPreferences) {
        self.preferences = preferences
        if style != preferences.style { style = preferences.style }
        if theme != preferences.theme { theme = preferences.theme }
    }

    func load() {
        isLoading = true
        do {
            chapters = try provider.chapters(for: book)
            if let initialChapter {
                chapterIndex = min(max(initialChapter, 0), max(chapters.count - 1, 0))
                pendingPage = nil
            } else if let saved = positionStore.restore(bookId: book.id, chapterCount: chapters.count) {
                chapterIndex = saved.chapterIndex
                pendingPage = saved.pageIndex
                log?.append("恢复位置：第 \(saved.chapterIndex + 1) 章 第 \(saved.pageIndex + 1) 页")
            } else {
                log?.append("无历史位置，从第 1 章开始")
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
        applyPendingPage()
    }

    /// 分页尺寸拿到之后才知道总页数，所以页码要等第一次重排完再落。
    private func applyPendingPage() {
        guard let pending = pendingPage else { return }
        pageIndex = min(max(pending, 0), max(pageRanges.count - 1, 0))
        pendingPage = nil
    }

    func repaginate() {
        guard lastPageSize.width > 40, let attributed = chapterAttributed() else { return }
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
        guard pageRanges.indices.contains(pageIndex),
              let attributed = chapterAttributed() else {
            return NSAttributedString(string: "")
        }
        let range = pageRanges[pageIndex]
        guard range.location + range.length <= attributed.length else { return attributed }

        let page = NSMutableAttributedString(attributedString: attributed.attributedSubstring(from: range))
        applySpeechHighlight(to: page, pageRange: range)
        return page
    }

    /// 整章富文本只构建一次。分页、朗读切句、高亮都基于同一份字符串，
    /// 否则句子的偏移和页的范围会错位，高亮就会漂。
    private func chapterAttributed() -> NSAttributedString? {
        guard let chapter = currentChapter else { return nil }
        let key = CacheKey(chapter: chapterIndex, style: style, theme: theme.rawValue)
        if key == cachedKey, let cached = cachedAttributed { return cached }

        let built = attributedBody(for: chapter)
        cachedAttributed = built
        cachedKey = key
        return built
    }

    private var speechHighlightColor: UIColor {
        theme.isDark
            ? UIColor(white: 1, alpha: 0.16)
            : UIColor(red: 0.72, green: 0.36, blue: 0.24, alpha: 0.14)
    }

    private func applySpeechHighlight(to page: NSMutableAttributedString, pageRange: NSRange) {
        guard let speechIndex, speechSentences.indices.contains(speechIndex) else { return }
        let sentence = speechSentences[speechIndex]

        let overlap = NSIntersectionRange(sentence.range, pageRange)
        guard overlap.length > 0 else { return }

        let local = NSRange(location: overlap.location - pageRange.location, length: overlap.length)
        guard local.location >= 0, local.location + local.length <= page.length else { return }
        page.addAttribute(.backgroundColor, value: speechHighlightColor, range: local)
    }

    // MARK: 翻页

    func turnPage(by delta: Int) {
        guard !chapters.isEmpty else { return }
        pendingPage = nil
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
    ///
    /// 以前跨章返回 nil，调用方就 `snapBack()` —— 于是「本章最后一页」往左滑永远弹回去，
    /// 进不了下一章。现在跨章时把相邻章的首/尾页也排出来，动画照常推进，
    /// 动画结束后再真正换章。
    func pageText(offset: Int) -> NSAttributedString? {
        let target = pageIndex + offset

        if pageRanges.indices.contains(target) {
            guard let attributed = chapterAttributed() else { return nil }
            return slice(attributed, pageRanges[target])
        }

        let neighbor = chapterIndex + (offset > 0 ? 1 : -1)
        guard chapters.indices.contains(neighbor), lastPageSize.width > 40 else { return nil }

        let attributed = attributedBody(for: chapters[neighbor])
        let ranges = Paginator.pageRanges(attributedString: attributed, pageSize: lastPageSize)
        guard let range = offset > 0 ? ranges.first : ranges.last else { return nil }
        return slice(attributed, range)
    }

    private func slice(_ attributed: NSAttributedString, _ range: NSRange) -> NSAttributedString? {
        guard range.location >= 0,
              range.location + range.length <= attributed.length else { return nil }
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
        pendingPage = nil
        chapterIndex = index
        repaginate()
        pageIndex = 0
        persistProgress()
    }

    // MARK: 持久化

    /// 保存阅读位置。
    /// 以前整个函数用 `try?` 包着，写失败完全没有痕迹——这就是"读到第 4 章、下次回到第 1 章"
    /// 查不出来的原因。现在失败会写进日志，成功也会读回来核对一次。
    func persistProgress(force: Bool = false) {
        guard chapters.count > 0 else { return }

        let now = Date().timeIntervalSince1970
        guard force || now - lastSavedAt > 1 else { return }
        lastSavedAt = now

        let position = ReadingPosition(chapterIndex: chapterIndex, pageIndex: pageIndex)
        do {
            guard let record = try positionStore.save(
                bookId: book.id,
                position: position,
                pageCount: pageCount,
                chapterCount: chapters.count,
                timestamp: Int(now)
            ) else { return }

            let verified = positionStore.verify(bookId: book.id, expecting: record)
            if !verified {
                log?.append("保存位置校验失败：期望第 \(record.chapterIndex + 1) 章，读回不一致")
            } else if record.chapterIndex != lastLoggedChapter {
                lastLoggedChapter = record.chapterIndex
                log?.append("保存位置：第 \(record.chapterIndex + 1) 章，全书 \(Int(record.percent * 100))%")
            }

            try? booksRepo.touch(bookId: book.id, at: Int(now))
        } catch {
            log?.append("保存位置失败：\(error.localizedDescription)")
        }
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

    // MARK: 朗读

    var isSpeechPrepared: Bool { speechQueue != nil }

    /// 准备朗读：从当前页的第一句开始，返回要念的文本。
    /// 不从头念——你已经看到哪，它就念哪。
    func prepareSpeech(startAtCurrentPage: Bool = true) -> String? {
        guard let attributed = chapterAttributed(), attributed.length > 0 else { return nil }
        let key = CacheKey(chapter: chapterIndex, style: style, theme: theme.rawValue)

        if speechSentenceKey != key || speechSentences.isEmpty {
            speechSentences = SentenceSplitter.split(attributed.string)
            speechSentenceKey = key
        }
        guard !speechSentences.isEmpty else { return nil }

        var start = 0
        if startAtCurrentPage, pageRanges.indices.contains(pageIndex) {
            // 章标题排在正文前面，但它不是正文。从章首开始听时跳过标题，
            // 否则"那一页的第一句"（正文第一句）会被标题顶掉。
            let titleLength = (currentChapter?.title as NSString?)?.length ?? 0
            start = SpeechStartLocator.startIndex(
                sentences: speechSentences,
                pageLocation: pageRanges[pageIndex].location,
                titleLength: titleLength
            )
        }

        speechQueue = SpeechQueue(sentences: speechSentences, index: start)
        speechIndex = speechQueue?.index
        // 这里**不要**再 syncPageToSpeech：起点本来就取自当前页，
        // 同步只会在句子跨页时把刚翻过去的那一页又拉回上一页。
        // 自动往下念时的翻页由 advanceSpeechText 内部的 sync 负责。
        return speechQueue?.current?.text
    }

    /// 念下一句。返回 nil 表示本章念完了。
    func advanceSpeechText() -> String? {
        guard var queue = speechQueue else { return nil }
        guard queue.advance() else { return nil }
        speechQueue = queue
        speechIndex = queue.index
        syncPageToSpeech()
        return queue.current?.text
    }

    /// 回到上一句。已经在第一句时重新念当前这句。
    func rewindSpeechText() -> String? {
        guard var queue = speechQueue else { return nil }
        if queue.rewind() {
            speechQueue = queue
            speechIndex = queue.index
            syncPageToSpeech()
        }
        return queue.current?.text
    }

    /// 本章念完，接着念下一章。返回下一章第一句的文本。
    func beginNextChapterForSpeech() -> String? {
        // 朗读已经被结束（退出阅读器、点了退出、定时到点）就别再跳章开念。
        // 之前这里只看章节边界，于是 stop 之后排队到来的 didFinish 会把下一章念起来。
        guard speechQueue != nil else { return nil }
        guard chapterIndex + 1 < chapters.count else { return nil }

        chapterIndex += 1
        pendingPage = nil
        pageIndex = 0
        cachedKey = nil
        cachedAttributed = nil
        speechSentenceKey = nil
        speechSentences = []
        repaginate()

        persistProgress(force: true)
        return prepareSpeech(startAtCurrentPage: true)
    }

    func endSpeech() {
        speechQueue = nil
        speechIndex = nil
    }

    /// 手动翻页后让朗读跟到当前页的第一句；不在朗读状态时返回 nil。
    func realignSpeechToCurrentPage() -> String? {
        guard speechQueue != nil else { return nil }
        return prepareSpeech(startAtCurrentPage: true)
    }

    var speechStatusText: String {
        // 队列已经没了还写"朗读中"，用户会以为卡死。如实说停了，点播放能重开。
        guard isSpeechPrepared else { return "朗读已停止" }
        guard let speechIndex, speechSentences.indices.contains(speechIndex) else {
            return "朗读中"
        }
        return "朗读中 · 第 \(chapterIndex + 1) 章 第 \(speechIndex + 1)/\(speechSentences.count) 句"
    }

    var speechDetailText: String {
        guard let speechIndex, speechSentences.indices.contains(speechIndex) else { return "" }
        let remaining = max(speechSentences.count - speechIndex - 1, 0)
        return "本章还剩 \(remaining) 句"
    }

    /// 让当前页跟上正在念的那一句。
    ///
    /// 先看当前页和这一句有没有交集：有一半在这页上就别翻。
    /// 以前只看句首位置，一句话跨页时会从下一页翻回上一页，用户看到的就是"页面自己往回跳"。
    private func syncPageToSpeech() {
        guard let sentence = speechQueue?.current else { return }

        if pageRanges.indices.contains(pageIndex) {
            let overlap = NSIntersectionRange(sentence.range, pageRanges[pageIndex])
            if overlap.length > 0 { return }
        }

        guard let target = pageRanges.firstIndex(where: { NSLocationInRange(sentence.location, $0) }) else {
            return
        }
        guard target != pageIndex else { return }
        pageIndex = target
        persistProgress(force: true)
    }
}
