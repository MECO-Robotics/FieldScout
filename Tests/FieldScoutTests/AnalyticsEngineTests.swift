import XCTest
@testable import FieldScout

final class AnalyticsEngineTests: XCTestCase {
    func testAggregatesTeamsWithoutChangingRows() {
        let team = SheetColumn(name: "Team", type: .integer, role: .teamNumber)
        let match = SheetColumn(name: "Match", type: .integer, role: .matchNumber)
        let auto = SheetColumn(name: "Auto", type: .decimal, role: .autoPoints)
        let teleop = SheetColumn(name: "Teleop", type: .decimal, role: .teleopPoints)
        let broke = SheetColumn(name: "Broke", type: .boolean, role: .breakdown)
        let originalRows = [
            ScoutingRow(values: [team.id: "111", match.id: "1", auto.id: "4", teleop.id: "6", broke.id: "yes"]),
            ScoutingRow(values: [team.id: "222", match.id: "1", auto.id: "8", teleop.id: "12", broke.id: "no"])
        ]
        let document = SheetDocument(
            title: "Test",
            columns: [team, match, auto, teleop, broke],
            rows: originalRows,
            updatedAt: .now
        )

        let result = AnalyticsEngine.analyze(document: document)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first(where: { $0.teamNumber == 111 })?.averageOffense, 10)
        XCTAssertEqual(result.first(where: { $0.teamNumber == 111 })?.breakdownRate, 1)
        XCTAssertEqual(result.first(where: { $0.teamNumber == 222 })?.breakdownRate, 0)
        XCTAssertEqual(document.rows, originalRows, "Analytics must not mutate the source sheet")
    }

    func testProjectedEPAIsShrunkTowardEventAverage() {
        let team = SheetColumn(name: "Team", type: .integer, role: .teamNumber)
        let score = SheetColumn(name: "Score", type: .decimal, role: .teleopPoints)
        let document = SheetDocument(
            title: "Test",
            columns: [team, score],
            rows: [
                ScoutingRow(values: [team.id: "1", score.id: "10"]),
                ScoutingRow(values: [team.id: "2", score.id: "20"])
            ],
            updatedAt: .now
        )

        let result = AnalyticsEngine.analyze(document: document)

        XCTAssertEqual(result.first(where: { $0.teamNumber == 1 })?.projectedEPA ?? 0, 13.333, accuracy: 0.001)
        XCTAssertEqual(result.first(where: { $0.teamNumber == 2 })?.projectedEPA ?? 0, 16.667, accuracy: 0.001)
    }
}
