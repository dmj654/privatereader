import Foundation
import GRDB

/// 书源表读写。原始 JSON 原样存，规则每次用的时候再解析——
/// 这样以后规则执行器升级，老源不用重新导入就能用上新能力。
public struct SourceRepository {
    private let db: any DatabaseWriter

    public init(db: any DatabaseWriter) {
        self.db = db
    }

    public func all() throws -> [BookSource] {
        try db.read {
            try BookSource.order(Column("name").asc).fetchAll($0)
        }
    }

    public func enabled() throws -> [BookSource] {
        try db.read {
            try BookSource.filter(Column("enabled") == true)
                .order(Column("name").asc)
                .fetchAll($0)
        }
    }

    public func fetch(id: String) throws -> BookSource? {
        try db.read { try BookSource.fetchOne($0, key: id) }
    }

    public func count() throws -> Int {
        try db.read { try BookSource.fetchCount($0) }
    }

    /// 返回 true 表示新增，false 表示覆盖已有。
    @discardableResult
    public func upsert(_ source: BookSource) throws -> Bool {
        try db.write { db in
            let exists = try BookSource.fetchOne(db, key: source.id) != nil
            try source.save(db)
            return !exists
        }
    }

    public func delete(id: String) throws {
        try db.write { _ = try BookSource.deleteOne($0, key: id) }
    }

    public func deleteAll() throws {
        try db.write { _ = try BookSource.deleteAll($0) }
    }

    public func setEnabled(id: String, enabled: Bool) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE source SET enabled = ? WHERE id = ?",
                arguments: [enabled, id]
            )
        }
    }

    public func markChecked(id: String, at timestamp: Int, result: String?) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE source SET lastCheckAt = ?, lastCheckResult = ? WHERE id = ?",
                arguments: [timestamp, result, id]
            )
        }
    }
}

// MARK: - 导入

public struct SourceImportSummary: Equatable, Sendable {
    public let added: Int
    public let updated: Int

    public var total: Int { added + updated }

    public init(added: Int, updated: Int) {
        self.added = added
        self.updated = updated
    }
}

/// 把 legado JSON 拆包、转成数据库行、覆盖写入。
public struct SourceImportService {
    private let repo: SourceRepository

    public init(repo: SourceRepository) {
        self.repo = repo
    }

    /// - Parameter forceEnabled: nil 沿用源自己的开关；true/false 强制覆盖。
    @discardableResult
    public func importJSON(_ data: Data, forceEnabled: Bool? = nil) throws -> SourceImportSummary {
        let parsed = try LegadoParser.parse(data: data)
        var added = 0
        var updated = 0

        for source in parsed {
            let record = BookSource(
                id: source.id,
                name: source.name,
                type: source.type,
                enabled: forceEnabled ?? source.enabled,
                rawJson: source.rawJson
            )
            if try repo.upsert(record) {
                added += 1
            } else {
                updated += 1
            }
        }

        return SourceImportSummary(added: added, updated: updated)
    }

    @discardableResult
    public func importJSON(_ text: String, forceEnabled: Bool? = nil) throws -> SourceImportSummary {
        guard let data = text.data(using: .utf8) else { throw LegadoParserError.invalidJSON }
        return try importJSON(data, forceEnabled: forceEnabled)
    }

    /// 从数据库里读一行，重新解析成可执行的源。
    public func executable(from record: BookSource) -> LegadoSource? {
        guard let data = record.rawJson.data(using: .utf8) else { return nil }
        guard let parsed = try? LegadoParser.parse(data: data).first else { return nil }
        var source = parsed
        source.enabled = record.enabled
        return source
    }
}
