import XCTest
@testable import FieldScout

@MainActor
final class SpreadsheetStoreTests: XCTestCase {
    func testConflictingScanCanReplaceExistingRow() throws {
        let store = makeStore()
        var first = Array(repeating: "", count: 29)
        first[0] = "AJ"
        first[1] = "7"
        first[2] = "8324"
        first[24] = "3"
        var second = first
        second[24] = "5"

        guard case .accepted = try store.ingestScan(first.joined(separator: "\t")) else {
            return XCTFail("The first scan should be accepted")
        }
        guard case .conflict(let conflict) = try store.ingestScan(second.joined(separator: "\t")) else {
            return XCTFail("The second scan should require conflict review")
        }

        XCTAssertEqual(conflict.teamNumber, 8324)
        XCTAssertEqual(conflict.matchNumber, 7)
        XCTAssertEqual(store.document.rows.count, 1)
        XCTAssertTrue(conflict.differences.contains { $0.columnName == "Defense Skill" && $0.previousValue == "3" && $0.scannedValue == "5" })

        store.resolveScanConflict(.replaceExisting)

        XCTAssertEqual(store.document.rows.count, 1)
        XCTAssertEqual(store.document.rows[0].values[store.document.columns[24].id], "5")
    }

    func testUndoCoalescesTypingInOneCell() {
        let store = makeStore()
        let row = store.document.rows[0]
        let column = store.document.columns[0]

        store.updateValue("A", rowID: row.id, columnID: column.id)
        store.updateValue("AJ", rowID: row.id, columnID: column.id)
        store.undo()

        XCTAssertEqual(store.value(rowID: row.id, columnID: column.id), "")
        XCTAssertTrue(store.canRedo)
    }

    func testManualBackupCanRestoreEarlierValues() {
        let store = makeStore()
        let row = store.document.rows[0]
        let column = store.document.columns[0]
        store.updateValue("before", rowID: row.id, columnID: column.id)
        store.createManualBackup()
        guard let backup = store.backups.first else { return XCTFail("Expected a backup") }

        store.updateValue("after", rowID: row.id, columnID: column.id)
        store.restoreBackup(backup)

        XCTAssertEqual(store.value(rowID: row.id, columnID: column.id), "before")
    }

    private func makeStore() -> SpreadsheetStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FieldScoutTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return SpreadsheetStore(storageDirectory: directory)
    }
}
