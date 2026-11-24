import XCTest
import GRDB
@testable import ReaderCore

final class DatabaseTests: XCTestCase {
    func testMigrationCreatesAllTables() throws {
        let database = try AppDatabase.inMemory()
        let tables = try database.writer.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
        }
        let expected = ["book", "bookGroup", "bookmark", "chapterCache", "progress",
                        "readingSession", "searchHistory", "source"]
        XCTAssertEqual(tables.sorted(), expected.sorted())
    }

    func testSeedCreatesThreeBuiltinGroups() throws {
        let database = try AppDatabase.inMemory()
        let groups = try GroupRepository(db: database.writer).all()
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.map(\.name), ["在追", "看完", "弃了"])
        XCTAssertTrue(groups.allSatisfy(\.builtin))
    }

    func testMigrationIsIdempotentOnSameFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("db-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try AppDatabase.open(at: url)
        XCTAssertEqual(try GroupRepository(db: first.writer).all().count, 3)

        let second = try AppDatabase.open(at: url)
        XCTAssertEqual(try GroupRepository(db: second.writer).all().count, 3)
    }

    func testForeignKeysEnabled() throws {
        let database = try AppDatabase.inMemory()
        let enabled = try database.writer.read { db in
            try Int.fetchOne(db, sql: "PRAGMA foreign_keys") ?? 0
        }
        XCTAssertEqual(enabled, 1)
    }
}
