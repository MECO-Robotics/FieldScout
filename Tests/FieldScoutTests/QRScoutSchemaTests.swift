import XCTest
@testable import FieldScout

final class QRScoutSchemaTests: XCTestCase {
    private let expectedHeaders = [
        "Scouter Initials", "Match Number", "Team Number", "Starting Position", "No Show",
        "Fuel Scored", "Where collected Fuel", "Other Auto actions",
        "Robot Stuck or a Stop in Auto", "Climbed", "Fuel Scored", "Bump Trench",
        "Deffended by Opponent", "Fuel Fed", "Opposing Zone Actions", "Climbed",
        "Mechanical Issue", "Died", "Triped/Fell Over", "Scoring Efectiveness",
        "Scored How?", "Scoring Location", "Feeding/Passing Skill", "Passed How?",
        "Defense Skill", "Yello/Red Card", "First Pick", "Second Pick", "Comments"
    ]

    func testStarterSheetMatchesQRScoutLegacyContractExactly() {
        let document = SheetDocument.starter()

        XCTAssertEqual(document.title, "MECO QRScout 2026")
        XCTAssertEqual(document.columns.count, 29)
        XCTAssertEqual(document.columns.map(\.name), expectedHeaders)
        XCTAssertEqual(document.columns[1].role, .matchNumber)
        XCTAssertEqual(document.columns[2].role, .teamNumber)
        XCTAssertEqual(document.columns[5].role, .autoPoints)
        XCTAssertEqual(document.columns[9].role, .autoPoints)
        XCTAssertEqual(document.columns[10].role, .teleopPoints)
        XCTAssertEqual(document.columns[15].role, .endgamePoints)
        XCTAssertEqual(document.columns[16].role, .breakdown)
        XCTAssertEqual(document.columns[17].role, .breakdown)
        XCTAssertEqual(document.columns[18].role, .breakdown)
        XCTAssertEqual(document.columns[24].role, .defenseRating)
        XCTAssertEqual(QRScoutSchema.expandedStartingPosition("OBFH"), "Outpost Bump — Hub")
        XCTAssertEqual(QRScoutSchema.expandedStartingPosition("Depot Trench"), "Depot Trench")
        XCTAssertEqual(
            QRScoutSchema.expandedValue("1,3", forColumnNamed: "Where collected Fuel"),
            "Outpost, Neutral Zone"
        )
        XCTAssertEqual(
            QRScoutSchema.expandedValue("1,6", forColumnNamed: "Scoring Location"),
            "Outpost Trench, Depot Trench"
        )
    }

    func testExactLegacyPayloadBecomesQRScoutScan() throws {
        let values = [
            "AJ", "12", "8324", "OT", "false", "500", "1,3", "1,2", "true", "C",
            "450", "1,2", "true", "300", "1,2", "L3", "true", "false", "true",
            "5", "both", "1,3", "4", "stationary", "5", "Yellow", "Yes", "May", "solid"
        ]

        let result = try ScanPayloadService.parse(values.joined(separator: "\t"))

        XCTAssertEqual(result, .qrScoutLegacy(values))
    }

    func testEmptyFirstAndLastQRScoutFieldsRemainInTheirColumns() throws {
        var values = Array(repeating: "0", count: QRScoutSchema.fieldCount)
        values[0] = ""
        values[28] = ""

        let result = try ScanPayloadService.parse(values.joined(separator: "\t"))

        XCTAssertEqual(result, .qrScoutLegacy(values))
    }

    func testQRScoutScoringAndBreakdownMappings() {
        let columns = QRScoutSchema.columns()
        let payload = [
            "AJ", "7", "8324", "OT", "false", "12", "1,3", "", "false", "C",
            "40", "1,2", "false", "18", "", "L2", "false", "true", "false",
            "5", "both", "1,3", "4", "stationary", "4", "No Card", "Yes", "Yes", ""
        ]
        let values = Dictionary(uniqueKeysWithValues: zip(columns.map(\.id), payload))
        let document = SheetDocument(
            title: "Test",
            columns: columns,
            rows: [ScoutingRow(values: values)],
            updatedAt: .now
        )

        let result = AnalyticsEngine.analyze(document: document)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].teamNumber, 8324)
        XCTAssertEqual(result[0].averageAuto, 27, "12 fuel + 15-point AUTO climb")
        XCTAssertEqual(result[0].averageTeleop, 40)
        XCTAssertEqual(result[0].averageEndgame, 20, "LEVEL 2 climb")
        XCTAssertEqual(result[0].averageOffense, 87)
        XCTAssertEqual(result[0].averageDefense, 4)
        XCTAssertEqual(result[0].breakdownRate, 1, "Died=true makes this a breakdown")
    }
}
