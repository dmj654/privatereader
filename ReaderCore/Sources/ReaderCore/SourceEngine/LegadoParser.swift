import Foundation

public enum LegadoParserError: LocalizedError, Equatable {
    case invalidJSON
    case empty

    public var errorDescription: String? {
        switch self {
        case .invalidJSON: return "这不是有效的 JSON 文件"
        case .empty: return "文件里没有可用的书源"
        }
    }
}

/// legado（开源阅读）书源导入。
///
/// 两种常见结构都要吃：
/// - 顶层数组：`[{...}, {...}]`，2500 源合集就是这种；
/// - 顶层单个对象：`{...}`，网友分享的单条源。
///
/// 解析只做"拆包 + 取字段"，不碰规则语义。规则怎么执行是 `RuleRunner` 的事。
public enum LegadoParser {

    public static func parse(json: String) throws -> [LegadoSource] {
        guard let data = json.data(using: .utf8) else { throw LegadoParserError.invalidJSON }
        return try parse(data: data)
    }

    public static func parse(data: Data) throws -> [LegadoSource] {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw LegadoParserError.invalidJSON
        }

        let dicts: [[String: Any]]
        if let array = root as? [[String: Any]] {
            dicts = array
        } else if let single = root as? [String: Any] {
            // 有些导出包会套一层：{"bookSources": [...]}
            if let nested = single["bookSources"] as? [[String: Any]] {
                dicts = nested
            } else if let nested = single["data"] as? [[String: Any]] {
                dicts = nested
            } else {
                dicts = [single]
            }
        } else {
            throw LegadoParserError.invalidJSON
        }

        var result: [LegadoSource] = []
        var seen = Set<String>()

        for (index, dict) in dicts.enumerated() {
            guard let source = source(from: dict, index: index) else { continue }
            // 同一个 URL 只留第一条：不少合集里会重复收录
            guard seen.insert(source.id).inserted else { continue }
            result.append(source)
        }

        guard !result.isEmpty else { throw LegadoParserError.empty }
        return result
    }

    // MARK: 单条

    private static func source(from dict: [String: Any], index: Int) -> LegadoSource? {
        let name = string(dict, "bookSourceName").trimmingCharacters(in: .whitespacesAndNewlines)
        let url = string(dict, "bookSourceUrl").trimmingCharacters(in: .whitespacesAndNewlines)
        // 名字和地址都空的条目没有意义，通常是占位项
        guard !name.isEmpty || !url.isEmpty else { return nil }

        let raw = rawJSONString(dict)

        let search = dictValue(dict, "ruleSearch")
        let info = dictValue(dict, "ruleBookInfo")
        let toc = dictValue(dict, "ruleToc")
        let content = dictValue(dict, "ruleContent")

        return LegadoSource(
            id: url.isEmpty ? "source-\(index)-\(name)" : url,
            name: name.isEmpty ? url : name,
            url: url,
            type: int(dict, "bookSourceType"),
            enabled: bool(dict, "enabled", fallback: true),
            header: string(dict, "header").isEmpty ? nil : string(dict, "header"),
            searchUrl: string(dict, "searchUrl"),
            exploreUrl: string(dict, "exploreUrl").isEmpty ? nil : string(dict, "exploreUrl"),
            ruleSearch: SearchRule(
                bookList: string(search, "bookList"),
                name: string(search, "name"),
                author: string(search, "author"),
                kind: string(search, "kind"),
                wordCount: string(search, "wordCount"),
                lastChapter: string(search, "lastChapter"),
                intro: string(search, "intro"),
                coverUrl: string(search, "coverUrl"),
                bookUrl: string(search, "bookUrl")
            ),
            ruleBookInfo: BookInfoRule(
                name: string(info, "name"),
                author: string(info, "author"),
                kind: string(info, "kind"),
                wordCount: string(info, "wordCount"),
                lastChapter: string(info, "lastChapter"),
                intro: string(info, "intro"),
                coverUrl: string(info, "coverUrl"),
                tocUrl: string(info, "tocUrl")
            ),
            ruleToc: TocRule(
                chapterList: string(toc, "chapterList"),
                chapterName: string(toc, "chapterName"),
                chapterUrl: string(toc, "chapterUrl"),
                updateTime: string(toc, "updateTime"),
                nextTocUrl: string(toc, "nextTocUrl")
            ),
            ruleContent: ContentRule(
                content: string(content, "content"),
                nextContentUrl: string(content, "nextContentUrl")
            ),
            rawJson: raw
        )
    }

    // MARK: 取值（容忍 NSNumber / Bool / 缺失）

    private static func dictValue(_ dict: [String: Any], _ key: String) -> [String: Any] {
        dict[key] as? [String: Any] ?? [:]
    }

    private static func string(_ dict: [String: Any], _ key: String) -> String {
        if let value = dict[key] as? String { return value }
        if let value = dict[key] as? NSNumber { return value.stringValue }
        return ""
    }

    private static func int(_ dict: [String: Any], _ key: String) -> Int {
        if let value = dict[key] as? Int { return value }
        if let value = dict[key] as? NSNumber { return value.intValue }
        if let value = dict[key] as? String { return Int(value) ?? 0 }
        return 0
    }

    private static func bool(_ dict: [String: Any], _ key: String, fallback: Bool) -> Bool {
        if let value = dict[key] as? Bool { return value }
        if let value = dict[key] as? NSNumber { return value.boolValue }
        if let value = dict[key] as? String {
            let lower = value.lowercased()
            if lower == "true" || lower == "1" { return true }
            if lower == "false" || lower == "0" { return false }
        }
        return fallback
    }

    private static func rawJSONString(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}
