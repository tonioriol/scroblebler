import XCTest
import GRDB
@testable import Scroblebler

final class MigrationTests: XCTestCase {

    /// A fresh database must migrate from scratch without errors.
    /// Regression test: v4 creates listens.image_url and v6 used to add it
    /// again, which crashed fresh installs with "duplicate column name".
    func testFreshDatabaseMigratesFromScratch() throws {
        let dbQueue = try DatabaseQueue()
        try LocalDatabase().migrator.migrate(dbQueue)

        let columns = try dbQueue.read { db in
            try db.columns(in: "listens").map(\.name)
        }
        XCTAssertTrue(columns.contains("image_url"))
    }
}
