import Foundation
import SwiftSoup

/// 书源网络层：搜索 / 详情 / 目录 / 正文。
///
/// 单独做成 actor，是因为一次搜索会同时打十几个源；
/// 每个源内部串行、源与源之间并行，互不阻塞。
public actor SourceClient {

    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: 搜索

    public func search(source: LegadoSource, key: String, page: Int = 1) async throws -> [OnlineBook] {
        guard !source.searchUrl.isEmpty else { throw SourceError.emptyRule("搜索") }
        guard !source.ruleSearch.bookList.isEmpty else { throw SourceError.emptyRule("搜索列表") }

        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
        let url = source.searchUrl
            .replacingOccurrences(of: "{{key}}", with: encodedKey)
            .replacingOccurrences(of: "{{page}}", with: "\(page)")

        let html = try await fetch(url, source: source)
        let items = RuleRunner.elements(source.ruleSearch.bookList, html: html, baseUrl: source.url)

        return map(items, rule: source.ruleSearch, source: source)
    }

    private func map(_ items: [String], rule: SearchRule, source: LegadoSource) -> [OnlineBook] {
        items.compactMap { item in
            let name = RuleRunner.string(rule.name, html: item, baseUrl: source.url)
            guard !name.isEmpty else { return nil }
            return OnlineBook(
                sourceId: source.id,
                name: name,
                author: RuleRunner.string(rule.author, html: item, baseUrl: source.url),
                coverUrl: RuleRunner.string(rule.coverUrl, html: item, baseUrl: source.url),
                intro: RuleRunner.string(rule.intro, html: item, baseUrl: source.url),
                kind: RuleRunner.string(rule.kind, html: item, baseUrl: source.url),
                wordCount: RuleRunner.string(rule.wordCount, html: item, baseUrl: source.url),
                lastChapter: RuleRunner.string(rule.lastChapter, html: item, baseUrl: source.url),
                bookUrl: RuleRunner.resolveURL(
                    RuleRunner.string(rule.bookUrl, html: item, baseUrl: source.url),
                    baseUrl: source.url
                )
            )
        }
    }

    // MARK: 发现

    /// 从 exploreUrl 里拆出「分类名 :: 地址」。legado 用换行分隔每一项。
    /// 不把 `&&` 当分隔符——它是规则串联符，地址里也可能出现。
    public nonisolated func categories(source: LegadoSource) -> [ExploreCategory] {
        guard let raw = source.exploreUrl, !raw.isEmpty else { return [] }
        return raw.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.components(separatedBy: "::")
            guard parts.count >= 2 else { return nil }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let url = parts.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespaces)
            guard !url.isEmpty else { return nil }
            return ExploreCategory(name: name.isEmpty ? "全部" : name, url: url)
        }
    }

    public func explore(source: LegadoSource,
                        category: ExploreCategory,
                        page: Int = 1) async throws -> [OnlineBook] {
        guard !source.ruleExplore.bookList.isEmpty else {
            throw SourceError.emptyRule("发现列表")
        }
        let url = category.url.replacingOccurrences(of: "{{page}}", with: "\(page)")
        let html = try await fetch(url, source: source)
        let items = RuleRunner.elements(source.ruleExplore.bookList, html: html, baseUrl: source.url)
        return map(items, rule: source.ruleExplore, source: source)
    }

    // MARK: 详情

    public func bookInfo(source: LegadoSource, book: OnlineBook) async throws -> OnlineBook {
        guard !book.bookUrl.isEmpty else { return book }
        let html = try await fetch(book.bookUrl, source: source)
        let rule = source.ruleBookInfo

        var result = book
        let name = RuleRunner.string(rule.name, html: html, baseUrl: source.url)
        if !name.isEmpty { result.name = name }
        let author = RuleRunner.string(rule.author, html: html, baseUrl: source.url)
        if !author.isEmpty { result.author = author }
        let cover = RuleRunner.string(rule.coverUrl, html: html, baseUrl: source.url)
        if !cover.isEmpty { result.coverUrl = cover }
        let intro = RuleRunner.string(rule.intro, html: html, baseUrl: source.url)
        if !intro.isEmpty { result.intro = intro }
        let kind = RuleRunner.string(rule.kind, html: html, baseUrl: source.url)
        if !kind.isEmpty { result.kind = kind }
        let words = RuleRunner.string(rule.wordCount, html: html, baseUrl: source.url)
        if !words.isEmpty { result.wordCount = words }
        let last = RuleRunner.string(rule.lastChapter, html: html, baseUrl: source.url)
        if !last.isEmpty { result.lastChapter = last }
        return result
    }

    // MARK: 目录

    public func chapters(source: LegadoSource, book: OnlineBook) async throws -> [OnlineChapter] {
        guard !source.ruleToc.chapterList.isEmpty else { throw SourceError.emptyRule("目录") }

        let detailHTML = try await fetch(book.bookUrl, source: source)
        let tocRule = source.ruleBookInfo.tocUrl
        let tocURL = tocRule.isEmpty
            ? book.bookUrl
            : RuleRunner.resolveURL(
                RuleRunner.string(tocRule, html: detailHTML, baseUrl: source.url),
                baseUrl: source.url
            )

        let tocHTML = tocURL == book.bookUrl ? detailHTML : try await fetch(tocURL, source: source)
        let items = RuleRunner.elements(source.ruleToc.chapterList, html: tocHTML, baseUrl: source.url)

        return items.compactMap { item in
            let name = RuleRunner.string(source.ruleToc.chapterName, html: item, baseUrl: source.url)
            let url = RuleRunner.resolveURL(
                RuleRunner.string(source.ruleToc.chapterUrl, html: item, baseUrl: source.url),
                baseUrl: source.url
            )
            guard !name.isEmpty, !url.isEmpty else { return nil }
            return OnlineChapter(
                name: name,
                url: url,
                updateTime: RuleRunner.string(source.ruleToc.updateTime, html: item, baseUrl: source.url)
            )
        }
    }

    // MARK: 正文

    public func content(source: LegadoSource, chapter: OnlineChapter) async throws -> String {
        guard !source.ruleContent.content.isEmpty else { throw SourceError.emptyRule("正文") }
        let html = try await fetch(chapter.url, source: source)
        let raw = RuleRunner.string(source.ruleContent.content, html: html, baseUrl: source.url)
        let text = Self.plainText(from: raw)
        guard !text.isEmpty else { throw SourceError.emptyContent }
        return text
    }

    // MARK: 漫画

    /// 漫画章的图片地址列表。
    /// 规则可能返回一段含 <img> 的 HTML，也可能直接返回若干个地址。
    public func comicPages(source: LegadoSource, chapter: OnlineChapter) async throws -> [String] {
        guard !source.ruleContent.content.isEmpty else { throw SourceError.emptyRule("正文") }
        let html = try await fetch(chapter.url, source: source)
        let raw = RuleRunner.string(source.ruleContent.content, html: html, baseUrl: source.url)
        let urls = Self.imageURLs(in: raw, base: source.url)
        guard !urls.isEmpty else { throw SourceError.emptyContent }
        return urls
    }

    /// 漫画站的图片大多防盗链，下载时必须带 Referer 和源里配置的 header。
    public nonisolated func imageHeaders(source: LegadoSource) -> [String: String] {
        var headers = [
            "User-Agent": userAgent,
            "Accept-Language": "zh-CN,zh;q=0.9"
        ]
        for (key, value) in Self.parseHeader(source.header) {
            headers[key] = value
        }
        if headers["Referer"] == nil {
            headers["Referer"] = source.url
        }
        return headers
    }

    static func imageURLs(in raw: String, base: String) -> [String] {
        if let doc = try? SwiftSoup.parse(raw),
           let images = try? doc.select("img").array(),
           !images.isEmpty {
            var result: [String] = []
            for element in images {
                let src = (try? element.attr("src")) ?? ""
                let lazy = (try? element.attr("data-src")) ?? ""
                let original = (try? element.attr("data-original")) ?? ""

                var chosen = ""
                if !src.isEmpty, !src.hasPrefix("data:") {
                    chosen = src
                } else if !lazy.isEmpty {
                    chosen = lazy
                } else if !original.isEmpty {
                    chosen = original
                }
                if !chosen.isEmpty {
                    result.append(RuleRunner.resolveURL(chosen, baseUrl: base))
                }
            }
            return result
        }

        // 规则直接返回地址：换行 / 逗号 / 空格分隔
        let separators = CharacterSet(charactersIn: "\n\r,， \t")
        return raw.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { token in
                token.hasPrefix("http") || token.hasPrefix("/") || token.hasPrefix("//")
            }
            .map { RuleRunner.resolveURL($0, baseUrl: base) }
    }

    // MARK: 网络

    private func fetch(_ rawURL: String, source: LegadoSource) async throws -> String {
        let urlString = RuleRunner.resolveURL(rawURL, baseUrl: source.url)
        guard let url = URL(string: urlString) else { throw SourceError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        for (key, value) in Self.parseHeader(source.header) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw SourceError.cancelled
        }

        if let http = response as? HTTPURLResponse,
           !(200...399).contains(http.statusCode) {
            throw SourceError.http(http.statusCode)
        }

        guard let text = Self.decode(data: data, response: response) else {
            throw SourceError.decodingFailed
        }
        return text
    }

    // MARK: 编码

    static func parseHeader(_ raw: String?) -> [String: String] {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return object
    }

    static func decode(data: Data, response: URLResponse) -> String? {
        // 1. HTTP 头里的 charset
        if let http = response as? HTTPURLResponse,
           let contentType = http.value(forHTTPHeaderField: "Content-Type"),
           let name = charsetName(in: contentType),
           let encoding = encoding(for: name),
           let text = String(data: data, encoding: encoding) {
            return text
        }

        // 2. UTF-8
        if let text = String(data: data, encoding: .utf8) { return text }

        // 3. 页面 meta 里的 charset（GBK 站点常见）
        let head = data.prefix(4096)
        if let ascii = String(data: head, encoding: .isoLatin1),
           let name = charsetName(in: ascii),
           let encoding = encoding(for: name),
           let text = String(data: data, encoding: encoding) {
            return text
        }

        // 4. 最后用 GB18030 兜底：国内老站点绝大多数是它
        return String(data: data, encoding: gb18030)
    }

    private static func charsetName(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "charset\\s*=\\s*[\"']?([\\w-]+)",
                                                   options: [.caseInsensitive]) else { return nil }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        return (text as NSString).substring(with: match.range(at: 1)).lowercased()
    }

    private static func encoding(for name: String) -> String.Encoding? {
        switch name {
        case "utf-8", "utf8": return .utf8
        case "gbk", "gb2312", "gb18030", "gb-2312": return gb18030
        case "big5", "big-5": return String.Encoding(rawValue: 0x80000A03)
        default: return nil
        }
    }

    private static var gb18030: String.Encoding {
        let cf = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        return String.Encoding(rawValue: cf)
    }

    // MARK: 正文纯文本

    /// 把正文 HTML 转成带段落的纯文本。
    /// 直接 `element.text()` 会把所有换行压掉，读起来就是一大坨。
    static func plainText(from html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p\\s*>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</div\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<p[^>]*>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&ldquo;": "“", "&rdquo;": "”",
            "&hellip;": "…", "&mdash;": "—"
        ]
        for (key, value) in entities {
            text = text.replacingOccurrences(of: key, with: value)
        }

        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }
}
