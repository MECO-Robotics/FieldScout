import XCTest
@testable import FieldScout

final class DataQualityServiceTests: XCTestCase {
    func testReportsDuplicatePairInvalidRatingAndCoverage() {
        let columns = QRScoutSchema.columns()
        func row(initials: String) -> ScoutingRow {
            var values: [UUID: String] = [:]
            values[columns[0].id] = initials
            values[columns[1].id] = "9"
            values[columns[2].id] = "8324"
            values[columns[24].id] = "7"
            return ScoutingRow(values: values)
        }
        let document = SheetDocument(
            title: "Test",
            columns: columns,
            rows: [row(initials: "AJ"), row(initials: "MK")],
            updatedAt: .now
        )

        let summary = DataQualityService.analyze(document)

        XCTAssertEqual(summary.entryCount, 2)
        XCTAssertEqual(summary.rowsNeedingAttention, 2)
        XCTAssertEqual(summary.matches.first?.teamNumbers, [8324])
        XCTAssertEqual(summary.matches.first?.missingScoutCount, 5)
        XCTAssertTrue(summary.issues.contains { $0.message.contains("between 0 and 5") })
        XCTAssertTrue(summary.issues.contains { $0.message.contains("2 entries") })
    }

    func testCleanRowIsCountedAsValid() {
        let columns = QRScoutSchema.columns()
        var values: [UUID: String] = [:]
        values[columns[0].id] = "AJ"
        values[columns[1].id] = "12"
        values[columns[2].id] = "8324"
        values[columns[24].id] = "5"
        let document = SheetDocument(
            title: "Test",
            columns: columns,
            rows: [ScoutingRow(values: values)],
            updatedAt: .now
        )

        let summary = DataQualityService.analyze(document)

        XCTAssertEqual(summary.validEntryCount, 1)
        XCTAssertEqual(summary.rowsNeedingAttention, 0)
    }
}
