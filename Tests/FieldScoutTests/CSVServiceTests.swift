import XCTest
@testable import FieldScout

final class CSVServiceTests: XCTestCase {
    func testQuotedCSVParsing() {
        let parsed = CSVService.parse("Team,Notes\n254,\"Fast, reliable\"\n1678,\"Line one\nLine two\"\n")

        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[1], ["254", "Fast, reliable"])
        XCTAssertEqual(parsed[2], ["1678", "Line one\nLine two"])
    }

    func testRoleInferenceRecognizesCommonHeaders() {
        XCTAssertEqual(CSVService.inferRole(from: "Team Number"), .teamNumber)
        XCTAssertEqual(CSVService.inferRole(from: "Auto Points"), .autoPoints)
        XCTAssertEqual(CSVService.inferRole(from: "Robot Broke Down?"), .breakdown)
        XCTAssertEqual(CSVService.inferRole(from: "Driver Notes"), .none)
    }

    func testExactQRScoutCSVRestoresAnalyticsRoles() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qrscout-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        let row = [
            "AJ", "12", "8324", "OT", "false", "10", "1", "", "false", "C",
            "20", "1", "false", "5", "", "L2", "false", "true", "false",
            "4", "both", "1", "3", "driving", "5", "No Card", "Yes", "Yes", "solid"
        ]
        let csv = QRScoutSchema.headerNames.joined(separator: ",") + "\n"
            + row.joined(separator: ",") + "\n"
        try csv.write(to: url, atomically: true, encoding: .utf8)

        let document = try CSVService.importDocument(from: url)

        XCTAssertTrue(QRScoutSchema.matchesHeader(document.columns))
        XCTAssertEqual(document.columns[5].role, .autoPoints)
        XCTAssertEqual(document.columns[9].role, .autoPoints)
        XCTAssertEqual(document.columns[15].role, .endgamePoints)
        XCTAssertEqual(document.columns[17].role, .breakdown)
        XCTAssertEqual(document.columns[24].role, .defenseRating)
    }
}
