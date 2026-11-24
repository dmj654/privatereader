import Foundation

/// 章节正文的来源：首次打开解析原文件，之后走内存缓存。
/// 不写盘——本地书本来就在手机上，再存一份正文等于双倍占用。
public final class ChapterProvider {
    private let paths: SandboxPaths
    private let importer: ImportService
    private var cache: [String: [NovelChapter]] = [:]
    private let lock = NSLock()

    public init(paths: SandboxPaths, importer: ImportService = ImportService()) {
        self.paths = paths
        self.importer = importer
    }

    public func chapters(for book: Book) throws -> [NovelChapter] {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[book.id] { return cached }

        guard let filePath = book.filePath else {
            throw ImportError.unreadableFile(book.title)
        }
        let url = paths.root.appendingPathComponent(filePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportError.unreadableFile(book.title)
        }

        let content = try importer.parse(url: url)
        guard case .novel(let novel) = content else {
            throw ImportError.unsupportedFormat(url.pathExtension)
        }

        cache[book.id] = novel.chapters
        return novel.chapters
    }

    public func cachedChapterCount(bookId: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return cache[bookId]?.count
    }

    public func invalidate(bookId: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: bookId)
    }

    public func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}
