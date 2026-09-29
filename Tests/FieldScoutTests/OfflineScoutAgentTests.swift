import XCTest
@testable import FieldScout

final class OfflineScoutAgentTests: XCTestCase {
    func testSingleMatchBreakdownIsReportedAsOneHundredPercent() {
        let team = TeamAnalytics(
            teamNumber: 123,
            matches: 1,
            projectedEPA: 12,
            averageOffense: 10,
            averageAuto: 2,
            averageTeleop: 6,
            averageEndgame: 2,
            averageDefense: 3,
            breakdownRate: 1,
            performances: []
        )

        let response = OfflineScoutAgent.answer("Tell me about team 123", teams: [team])

        XCTAssertTrue(response.contains("100% breakdown rate"))
    }
}
