import XCTest
@testable import FieldScout

@MainActor
final class SpreadsheetStoreTests: XCTestCase {
    func testBarcodeScannedIntoOneCellIsDistributedAcrossTheRow() throws {
        let storage = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storage) }
        let store = SpreadsheetStore(storageDirectory: storage)
        let row = try XCTUnwrap(store.document.rows.first)
        let firstColumn = try XCTUnwrap(store.document.columns.first)
        let values = (0..<QRScoutSchema.fieldCount).map(String.init)

        store.updateValue(values.joined(separator: "<TAB>"), rowID: row.id, columnID: firstColumn.id)
        let result = try XCTUnwrap(store.ingestPackedCell(rowID: row.id, columnID: firstColumn.id))

        guard case .accepted = result else { return XCTFail("Packed cell scan should be accepted") }
        XCTAssertEqual(store.document.rows.count, 2)
        XCTAssertEqual(store.document.rows[0].values[store.document.columns[1].id], "1")
        XCTAssertEqual(store.document.rows[0].values[store.document.columns[2].id], "2")
        XCTAssertFalse(store.document.rows[0].values.values.contains(values.joined(separator: "<TAB>")))
        XCTAssertTrue(store.document.rows[1].values.values.allSatisfy(\.isEmpty))
    }

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
        XCTAssertEqual(store.document.rows.count, 2)
        XCTAssertTrue(conflict.differences.contains { $0.columnName == "Defense Skill" && $0.previousValue == "3" && $0.scannedValue == "5" })

        store.resolveScanConflict(.replaceExisting)

        XCTAssertEqual(store.document.rows.count, 2)
        XCTAssertEqual(store.document.rows[0].values[store.document.columns[24].id], "5")
    }

    func testStartingPositionCodeIsExpandedAndNextRowIsReady() throws {
        let store = makeStore()
        var fields = Array(repeating: "", count: QRScoutSchema.fieldCount)
        fields[0] = "AJ"
        fields[1] = "8"
        fields[2] = "8324"
        fields[3] = "DBFT"
        fields[6] = "1,3"
        fields[21] = "1,6"

        guard case .accepted = try store.ingestScan(fields.joined(separator: "\t")) else {
            return XCTFail("The scan should be accepted")
        }

        XCTAssertEqual(store.document.rows[0].values[store.document.columns[3].id], "Depot Bump — Trench")
        XCTAssertEqual(store.document.rows[0].values[store.document.columns[6].id], "Outpost, Neutral Zone")
        XCTAssertEqual(store.document.rows[0].values[store.document.columns[21].id], "Outpost Trench, Depot Trench")
        XCTAssertEqual(store.document.rows.count, 2)
        XCTAssertTrue(store.document.rows[1].values.values.allSatisfy(\.isEmpty))
        XCTAssertEqual(store.meaningfulRowCount, 1)
    }

    func testExistingNumericLocationsAreMigratedAndBlankRowIsRestoredOnLaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FieldScoutMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let columns = QRScoutSchema.columns()
        let values = [
            columns[0].id: "AJ",
            columns[3].id: "OT",
            columns[6].id: "2,4",
            columns[21].id: "3,5"
        ]
        let saved = SheetDocument(
            title: "Saved Event",
            columns: columns,
            rows: [ScoutingRow(values: values)],
            updatedAt: .now
        )
        try JSONEncoder().encode(saved).write(to: directory.appendingPathComponent("scouting-data.json"))

        let store = SpreadsheetStore(storageDirectory: directory)

        XCTAssertEqual(store.document.rows.count, 2)
        XCTAssertEqual(store.document.rows[0].values[columns[3].id], "Outpost Trench")
        XCTAssertEqual(store.document.rows[0].values[columns[6].id], "Depot, Neutral Zone — 2nd Pass")
        XCTAssertEqual(store.document.rows[0].values[columns[21].id], "Hub, Depot")
        XCTAssertTrue(store.document.rows[1].values.values.allSatisfy(\.isEmpty))
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
